//
//  AudioManager.swift
//  Downstep
//
//  Real-time generative audio engine. Instead of looping pre-baked audio files,
//  every sound is synthesized live from filtered noise shaped into four distinct
//  nature textures — rain, wind, ocean and birds — so nothing is a fixed loop and
//  there's no synth tone/hum competing with them.
//

import AVFoundation
import Combine
import UIKit

/// State machine for "Follow My Breath" mode, where the session's tempo is driven
/// by the listener's actual breathing (detected from the mic) instead of a fixed pace.
enum BreathFollowState: Equatable {
    case idle
    case calibrating
    case following
    case lost
}

/// One breath-rate reading at a point in the session, for the trend chart.
struct BreathReading: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let bpm: Double
}

final class AudioManager: ObservableObject {
    /// Keys for the four "make it yours" choices — remembered as the default
    /// for next time, but never assumed; each is only ever changed by an
    /// explicit tap on the Ready screen (or, for sound/atmosphere, mid-session).
    private enum PreferenceKeys {
        static let soundEnabled = "downstep.pref.soundEnabled"
        static let atmosphere = "downstep.pref.atmosphere"
        static let inputMode = "downstep.pref.inputMode"
        static let themeName = "downstep.pref.themeName"
    }

    @Published private(set) var isPlaying = false
    /// Seconds since the current session began — open-ended by design (no fixed
    /// timer/countdown); used only to timestamp breath-rate history.
    @Published private(set) var elapsed: TimeInterval = 0

    @Published var atmosphereStyle: AtmosphereStyle = {
        guard let raw = UserDefaults.standard.string(forKey: PreferenceKeys.atmosphere) else { return .rain }
        return AtmosphereStyle(rawValue: raw) ?? .rain
    }() {
        didSet {
            updateParams { $0.atmosphere = atmosphereStyle }
            UserDefaults.standard.set(atmosphereStyle.rawValue, forKey: PreferenceKeys.atmosphere)
        }
    }
    /// The visual/mood backdrop, chosen upfront and remembered — sets the mood
    /// only; it no longer silently overrides the atmosphere choice too (see
    /// `applyTheme`).
    @Published var preferredTheme: BreathTheme = .named(UserDefaults.standard.string(forKey: PreferenceKeys.themeName)) {
        didSet {
            UserDefaults.standard.set(preferredTheme.name, forKey: PreferenceKeys.themeName)
        }
    }
    /// Mic vs. touch — decided upfront on the Ready screen, remembered, and
    /// never silently switched once a session starts.
    @Published var preferredInputMode: BreathInputMode = {
        guard let raw = UserDefaults.standard.string(forKey: PreferenceKeys.inputMode) else { return .mic }
        return BreathInputMode(rawValue: raw) ?? .mic
    }() {
        didSet {
            UserDefaults.standard.set(preferredInputMode.rawValue, forKey: PreferenceKeys.inputMode)
        }
    }
    /// Overall spatial depth — drives the reverb's wet/dry mix.
    @Published var atmosphereAmount: Double = 0.45 {
        didSet { reverb.wetDryMix = Float(atmosphereAmount * 65) }
    }
    /// Noise / grain mix blended with the tonal bed.
    @Published var textureAmount: Double = 0.3 {
        didSet { updateParams { $0.texture = textureAmount } }
    }
    /// Rate and depth of the slow filter sweep that gives the sound motion.
    @Published var movementAmount: Double = 0.4 {
        didSet { updateParams { $0.movement = movementAmount } }
    }

    private(set) var currentSession: BreathTheme?

    // MARK: - Follow My Breath

    @Published private(set) var isFollowingBreath = false
    @Published private(set) var breathFollowState: BreathFollowState = .idle
    @Published private(set) var currentBPM: Double?
    /// The live breath envelope, 0...1, updated ~15x/sec while following — this is
    /// what a visual should bind to directly so the connection to the mic is
    /// immediate and undeniable, not just a derived rate.
    @Published private(set) var liveBreathLevel: Double = 0
    /// Breath rate readings across the session, for the end-of-session trend chart.
    @Published private(set) var bpmHistory: [BreathReading] = []
    /// Shown when breathing stays fast for a few readings in a row — a nudge, not a mode switch.
    @Published private(set) var guidanceMessage: String?
    /// A gentle target rate to pace toward while `guidanceMessage` is active — modestly
    /// slower than the current rate, recalculated as it's approached, not a fixed pace.
    @Published private(set) var guidanceTargetBPM: Double?
    /// A one-line takeaway shown when a followed session completes naturally.
    @Published private(set) var breathSummary: String?
    /// A plain, non-judgmental statement shown once breathing settles back down after
    /// guidance was active — a fact ("Breathing steady now"), never praise. Clears
    /// itself a few seconds after appearing.
    @Published private(set) var encouragementMessage: String?
    /// Seconds from when guidance first kicked in to when breathing settled back
    /// down — the most recently completed episode this session, if any.
    @Published private(set) var timeToCalmSeconds: Int?
    /// True only when `timeToCalmSeconds` genuinely beats the stored personal best.
    @Published private(set) var timeToCalmIsBest = false
    /// How many times the de-escalation curve has stepped down this session — the
    /// literal "downstep" count, surfaced on the summary screen.
    @Published private(set) var stepCount = 0
    /// The lowest guided rate reached this session, for the "24 to 8 breaths a
    /// minute" summary stat. Read alongside `stepCount` once a session ends.
    @Published private(set) var lowestGuidedBPM: Double?

    /// The breathing rate measured at the start of the session — used for the
    /// existing "slowed from ~X to ~Y" summary line and the step-count stat.
    @Published private(set) var startBPM: Double?
    private var calibrationSamples = 0
    private var calibrationStartDate: Date?
    private var lastDetectionDate: Date?
    private var fastBreathStreak = 0
    private let fastBreathThresholdBPM = 16.0
    /// The de-escalation glide path's current rung — nil when not actively guiding.
    private var deescalationCurveBPM: Double?
    private let deescalationStepBPM = 1.2
    private let deescalationFloorBPM = 6.0
    /// True once guidance has kicked in this streak — lets the "back to calm" message
    /// only appear as a genuine return from an elevated pace, not on every reading.
    private var wasGuiding = false
    /// Distinct from the drag track's phase-transition tap — a firmer, rarer pulse
    /// so each literal "downstep" in the guidance curve is felt, not just seen.
    private let stepHaptic = UIImpactFeedbackGenerator(style: .rigid)
    /// When the current guidance episode started — the clock for `timeToCalmSeconds`.
    private var guidanceStartedAt: Date?
    private static let bestTimeToCalmKey = "downstep.bestTimeToCalmSeconds"
    private var manualTapTimestamps: [Date] = []
    /// True once calibration has gone a few seconds with no clear mic signal — the
    /// UI should offer a manual tap-to-calibrate fallback at that point, for quiet
    /// breathing a mic (especially a laptop's, farther from your mouth) may miss.
    @Published private(set) var shouldOfferTapFallback = false
    /// True only when the listener explicitly chose "skip the mic" upfront (a noisy
    /// room, say) — unlike `shouldOfferTapFallback`, this doesn't clear the moment a
    /// signal comes through, since there's no mic to hand off to; the drag/tap track
    /// stays the primary interaction for the whole session.
    @Published private(set) var isManualModeChosen = false

    // Mic-tap-thread-only state (never touched off that callback).
    private var micLowpassState: Double = 0
    private var micEnvelope: Double = 0
    private var micSlowEnvelope: Double = 0
    private var micAboveThreshold = false
    private var lastPeakDate: Date?
    private var recentBreathPeriods: [Double] = []
    // Rolling range of the breath-envelope signal, so detection sensitivity adapts
    // to this device/mic/environment instead of assuming one fixed threshold.
    private var envelopeRangeMin: Double = 0.0004
    private var envelopeRangeMax: Double = 0.0008
    private var liveLevelPublishCounter = 0

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var sourceNode: AVAudioSourceNode!
    private let sampleRate: Double = 44_100
    private var timer: Timer?

    private let paramLock = NSLock()
    private var params = RenderParams()

    private struct RenderParams {
        var breathRate: Double = 0.10
        var breathDepth: Double = 0.5
        var texture: Double = 0.3
        var brightness: Double = 0.4
        var movement: Double = 0.4
        var atmosphere: AtmosphereStyle = .rain
        var fadeTarget: Double = 0
    }

    // Render-thread-only state (never touched off the audio thread).
    private var breathPhase: Double = 0
    private var lfoPhase: Double = 0
    private var gustPhase: Double = 0
    private var waveLfoPhase: Double = 0
    private var noiseFilterState: Double = 0
    private var noiseLowState: Double = 0
    private var pinkState = [Double](repeating: 0, count: 7)
    private var fadeGain: Double = 0

    // Rain droplet scheduler.
    private var rainDropSamplesRemaining = 0
    private var rainDropTotalSamples = 0
    private var samplesUntilNextDrop = 0
    private var dropFilterState: Double = 0

    // Bird chirp scheduler/oscillator.
    private var chirpSamplesRemaining = 0
    private var chirpTotalSamples = 0
    private var chirpPhaseAccum: Double = 0
    private var chirpFrequencyStart: Double = 3000
    private var chirpFrequencySweep: Double = 800
    private var samplesUntilNextChirp = 0

    init() {
        configureAudioSession()
        setupEngine()
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    private func setupEngine() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }

        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            self?.render(frameCount: frameCount, audioBufferList: audioBufferList) ?? noErr
        }

        engine.attach(sourceNode)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = Float(atmosphereAmount * 65)

        engine.connect(sourceNode, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0

        try? engine.start()
    }

    // MARK: - Transport

    /// Whether the generated nature-sound bed plays at all — off by default the
    /// very first time, then remembered like the other "make it yours" choices.
    @Published var soundEnabled: Bool = UserDefaults.standard.object(forKey: PreferenceKeys.soundEnabled) as? Bool ?? false {
        didSet {
            updateParams { $0.fadeTarget = (soundEnabled && isPlaying) ? 1 : 0 }
            UserDefaults.standard.set(soundEnabled, forKey: PreferenceKeys.soundEnabled)
        }
    }

    func applyTheme(_ theme: BreathTheme) {
        currentSession = theme
        // Atmosphere is its own upfront choice now (see `preferredTheme`) — the
        // backdrop only sets the visual mood and the mic-loss fallback pace,
        // it no longer silently overrides whatever sound the listener picked.
        textureAmount = theme.baseTexture
        movementAmount = 0.4
        updateParams { p in
            p.breathRate = theme.breathRate
            p.breathDepth = theme.breathDepth
            p.brightness = theme.baseBrightness
        }
    }

    /// Starts a session: applies the chosen mood/theme, begins the (silent unless
    /// `soundEnabled`) nature bed, and kicks off mic-based breath tracking.
    func beginSession(_ theme: BreathTheme) {
        breathSummary = nil
        elapsed = 0
        applyTheme(theme)
        resume()
        setFollowingBreath(true)
    }

    /// Starts a session with the mic never engaged at all — for a noisy room where
    /// ambient sound would read as a false breath signal, worse than no reading.
    /// Unlike the reactive tap/drag fallback (which hands off to the mic-driven orb
    /// the moment a signal comes through), this stays on the drag/tap track for the
    /// whole session, since there's no mic input to hand off to.
    func beginManualSession(_ theme: BreathTheme) {
        breathSummary = nil
        elapsed = 0
        applyTheme(theme)
        isManualModeChosen = true
        isFollowingBreath = true
        breathFollowState = .calibrating
        calibrationStartDate = Date()
        calibrationSamples = 0
        manualTapTimestamps.removeAll()
        bpmHistory.removeAll()
        startBPM = nil
        currentBPM = nil
        fastBreathStreak = 0
        deescalationCurveBPM = nil
        guidanceMessage = nil
        guidanceTargetBPM = nil
        wasGuiding = false
        encouragementMessage = nil
        guidanceStartedAt = nil
        timeToCalmSeconds = nil
        timeToCalmIsBest = false
        stepCount = 0
        lowestGuidedBPM = nil
        resume()
    }

    func resume() {
        isPlaying = true
        updateParams { $0.fadeTarget = soundEnabled ? 1 : 0 }
        startTimer()
    }

    func pause() {
        isPlaying = false
        updateParams { $0.fadeTarget = 0 }
        timer?.invalidate()
    }

    /// Ends the session early by the listener's own choice (as opposed to the timer
    /// running out) — same payoff summary either way.
    func finish() {
        completeSessionNaturally()
    }

    func stop() {
        pause()
        setFollowingBreath(false)
        currentSession = nil
        elapsed = 0
        breathSummary = nil
        // Otherwise this leaks into the next Ready screen: the drag/tap fallback
        // would render before a new session even starts, with nothing behind it
        // to actually receive its signals.
        shouldOfferTapFallback = false
        isManualModeChosen = false
        wasGuiding = false
        encouragementMessage = nil
        guidanceStartedAt = nil
        timeToCalmSeconds = nil
        timeToCalmIsBest = false
        stepCount = 0
        lowestGuidedBPM = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        elapsed += 1
        updateBreathWatchdog()
    }

    private func completeSessionNaturally() {
        pause()
        if let start = startBPM, let current = currentBPM {
            if current < start - 0.5 {
                breathSummary = "Your breathing slowed from ~\(Int(start.rounded())) to ~\(Int(current.rounded())) breaths a minute."
            } else {
                breathSummary = "You breathed steadily around ~\(Int(current.rounded())) breaths a minute."
            }
        }
    }

    // MARK: - Follow My Breath

    func setFollowingBreath(_ enabled: Bool) {
        guard enabled != isFollowingBreath else { return }
        isFollowingBreath = enabled
        enabled ? startBreathListening() : stopBreathListening()
    }

    private func startBreathListening() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.isFollowingBreath else { return }
                guard granted else {
                    // Declining the mic isn't a dead end — tap/drag tracking still
                    // works, and should be offered immediately rather than silently
                    // dropping back to idle with no path forward. `isFollowingBreath`
                    // stays true so `registerRhythmSignal()` keeps working; `.lost`
                    // reuses the existing "no live signal, here's the fallback" state
                    // rather than needing a separate one — the cause doesn't matter
                    // to the UI, only that a fallback is needed right now.
                    self.breathFollowState = .lost
                    self.shouldOfferTapFallback = true
                    self.revertToSessionBreathDefaults()
                    return
                }
                self.beginBreathCapture()
            }
        }
    }

    private func beginBreathCapture() {
        // Mutating the session's category/route while the engine is actively rendering
        // is what was crashing this — AVAudioEngine needs to be stopped before the I/O
        // configuration underneath it changes, then restarted once it's settled.
        engine.stop()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try session.setActive(true)
        } catch {
            isFollowingBreath = false
            breathFollowState = .idle
            try? engine.start()
            return
        }

        breathFollowState = .calibrating
        calibrationSamples = 0
        calibrationStartDate = Date()
        lastDetectionDate = nil
        lastPeakDate = nil
        micAboveThreshold = false
        micLowpassState = 0
        micEnvelope = 0
        micSlowEnvelope = 0
        envelopeRangeMin = 0.0004
        envelopeRangeMax = 0.0008
        recentBreathPeriods.removeAll()
        startBPM = nil
        currentBPM = nil
        bpmHistory.removeAll()
        fastBreathStreak = 0
        deescalationCurveBPM = nil
        guidanceMessage = nil
        guidanceTargetBPM = nil
        wasGuiding = false
        encouragementMessage = nil
        guidanceStartedAt = nil
        timeToCalmSeconds = nil
        timeToCalmIsBest = false
        stepCount = 0
        lowestGuidedBPM = nil
        liveBreathLevel = 0
        manualTapTimestamps.removeAll()
        shouldOfferTapFallback = false

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.processMicBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            isFollowingBreath = false
            breathFollowState = .idle
            input.removeTap(onBus: 0)
        }
    }

    private func stopBreathListening() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        breathFollowState = .idle
        revertToSessionBreathDefaults()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        try? engine.start()
    }

    private func revertToSessionBreathDefaults() {
        guard let session = currentSession else { return }
        updateParams { p in
            p.breathRate = session.breathRate
            p.breathDepth = session.breathDepth
        }
    }

    private func updateBreathWatchdog() {
        guard isFollowingBreath else { return }
        let now = Date()
        switch breathFollowState {
        case .calibrating:
            let calibratingFor = now.timeIntervalSince(calibrationStartDate ?? now)
            if calibratingFor > 5 && calibrationSamples == 0 {
                shouldOfferTapFallback = true
            }
            if calibratingFor > 18 {
                breathFollowState = .lost
                shouldOfferTapFallback = true
                revertToSessionBreathDefaults()
            }
        case .following:
            if let last = lastDetectionDate, now.timeIntervalSince(last) > 18 {
                breathFollowState = .lost
                shouldOfferTapFallback = true
                revertToSessionBreathDefaults()
            }
        case .lost, .idle:
            break
        }
    }

    /// Runs on the mic-tap's own callback thread — lightweight amplitude tracking only.
    private func processMicBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Breath sound is low-frequency broadband "whoosh," but a mic — especially a
        // Mac's built-in one, farther from your mouth than a phone — also picks up
        // fans, hum, and hiss well above that range. Lowpass the raw signal first so
        // detection is listening specifically for breath-like sound, not everything
        // in the room.
        let micSampleRate = buffer.format.sampleRate > 0 ? buffer.format.sampleRate : sampleRate
        let filterDt = 1.0 / micSampleRate
        let filterAlpha = filterDt / (1.0 / (2 * Double.pi * 800.0) + filterDt)

        var sum: Double = 0
        for i in 0..<frameCount {
            micLowpassState += filterAlpha * (Double(channelData[i]) - micLowpassState)
            sum += micLowpassState * micLowpassState
        }
        let rms = sqrt(sum / Double(frameCount))

        micEnvelope += 0.35 * (rms - micEnvelope)
        micSlowEnvelope += 0.01 * (rms - micSlowEnvelope)
        let ac = micEnvelope - micSlowEnvelope

        // Adaptive threshold: track a slowly-decaying peak and a slowly-rising floor
        // of the breath signal so sensitivity calibrates to this device/room instead
        // of assuming one fixed number works everywhere.
        if ac > envelopeRangeMax {
            envelopeRangeMax = ac
        } else {
            envelopeRangeMax *= 0.999997
        }
        if ac < envelopeRangeMin {
            envelopeRangeMin = ac
        } else {
            envelopeRangeMin += (ac - envelopeRangeMin) * 0.000003
        }
        let range = max(envelopeRangeMax - envelopeRangeMin, 0.0003)
        let riseThreshold = envelopeRangeMin + range * 0.28
        let fallThreshold = envelopeRangeMin + range * 0.12

        // Require real observed signal, not just relative range, before trusting a
        // crossing — otherwise near-silence (tiny fan/electrical noise fluctuations)
        // can cross its own tiny adaptive range and register as a false breath.
        let hasRealSignal = envelopeRangeMax > 0.0008

        let now = Date()
        if hasRealSignal && ac > riseThreshold && !micAboveThreshold {
            micAboveThreshold = true
            if let last = lastPeakDate {
                let period = now.timeIntervalSince(last)
                // Allow up to ~75 breaths/min so hard, fast (panting/running-style)
                // breathing actually registers instead of being discarded as noise —
                // the old 1.5s floor capped detection at 40/min.
                if period > 0.8 && period < 15 {
                    recentBreathPeriods.append(period)
                    // A shorter averaging window reacts to a sudden change of pace
                    // (calm to panting, or back down again) within 2-3 breaths instead
                    // of being dragged out by older, slower readings.
                    if recentBreathPeriods.count > 3 { recentBreathPeriods.removeFirst() }
                    let avgPeriod = recentBreathPeriods.reduce(0, +) / Double(recentBreathPeriods.count)
                    let bpm = 60.0 / avgPeriod
                    DispatchQueue.main.async { [weak self] in
                        self?.applyDetectedBreath(period: avgPeriod, bpm: bpm)
                    }
                }
            }
            lastPeakDate = now
        } else if ac < fallThreshold {
            micAboveThreshold = false
        }

        // Publish the live, normalized envelope for the visual to bind to directly —
        // throttled so it doesn't flood the main thread with every buffer callback.
        liveLevelPublishCounter += 1
        if liveLevelPublishCounter >= 3 {
            liveLevelPublishCounter = 0
            let normalized = max(0, min(1, (ac - envelopeRangeMin) / range))
            DispatchQueue.main.async { [weak self] in
                self?.liveBreathLevel = normalized
            }
        }
    }

    private func applyDetectedBreath(period: Double, bpm: Double) {
        guard isFollowingBreath else { return }
        lastDetectionDate = Date()

        if breathFollowState == .calibrating {
            calibrationSamples += 1
            if calibrationSamples >= 1 {
                breathFollowState = .following
                startBPM = bpm
            }
        } else if breathFollowState == .lost {
            breathFollowState = .following
        }

        shouldOfferTapFallback = false
        currentBPM = bpm

        if breathFollowState == .following {
            updateParams { p in
                p.breathRate = 1.0 / period
                p.breathDepth = 0.6
            }

            bpmHistory.append(BreathReading(time: elapsed, bpm: bpm))
            if bpmHistory.count > 60 { bpmHistory.removeFirst() }

            if bpm > fastBreathThresholdBPM {
                fastBreathStreak += 1
                if fastBreathStreak >= 2 {
                    if !wasGuiding {
                        wasGuiding = true
                        guidanceStartedAt = Date()
                    }
                    // Plain, factual language throughout — no coach-style praise or
                    // evaluation ("you've got this"), which reads badly, especially
                    // for men. Once guidance has been running a while, say so rather
                    // than repeating the opening line every reading.
                    guidanceMessage = fastBreathStreak > 5 ? "Still easing down" : "Let's slow it down together"
                    // A real glide path, not a reactive "current minus 2": once
                    // triggered, the target steps down by a fixed safe amount every
                    // breath regardless of what the listener's actual rate does,
                    // easing from wherever they started toward a calm floor. Forcing
                    // an instant jump to 6/min from a panicked pace risks air-hunger
                    // and can spike panic further — small steady steps don't.
                    let baseline = deescalationCurveBPM ?? min(bpm, 40)
                    let nextRung = max(deescalationFloorBPM, baseline - deescalationStepBPM)
                    if nextRung < baseline {
                        stepHaptic.impactOccurred()
                        stepCount += 1
                        lowestGuidedBPM = min(lowestGuidedBPM ?? nextRung, nextRung)
                    }
                    deescalationCurveBPM = nextRung
                    guidanceTargetBPM = deescalationCurveBPM
                }
            } else {
                fastBreathStreak = 0
                guidanceMessage = nil
                guidanceTargetBPM = nil
                deescalationCurveBPM = nil
                if wasGuiding {
                    wasGuiding = false
                    encouragementMessage = "Breathing steady now"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                        self?.encouragementMessage = nil
                    }
                    if let startedAt = guidanceStartedAt {
                        let seconds = max(1, Int(Date().timeIntervalSince(startedAt).rounded()))
                        timeToCalmSeconds = seconds
                        let defaults = UserDefaults.standard
                        let storedBest = defaults.object(forKey: Self.bestTimeToCalmKey) as? Int
                        if storedBest == nil || seconds < storedBest! {
                            timeToCalmIsBest = true
                            defaults.set(seconds, forKey: Self.bestTimeToCalmKey)
                        } else {
                            timeToCalmIsBest = false
                        }
                    }
                    guidanceStartedAt = nil
                }
            }
        }
    }

    /// Manual fallback for when the mic can't pick up a clear signal (quiet breathing,
    /// a noisy room, or a laptop mic farther from your mouth than a phone). Called once
    /// per completed breath — by a tap, or by a full drag-track cycle — after a couple
    /// of signals this feeds the exact same pipeline mic detection does, so tracking,
    /// guidance, and the trend chart all work identically no matter which input it was.
    /// Called only when the listener explicitly taps the "switch to touch"
    /// hint after the mic goes quiet — the fallback is offered, never
    /// silently applied. This is what actually swaps in the drag track.
    func confirmManualFallback() {
        isManualModeChosen = true
    }

    func registerRhythmSignal() {
        guard isFollowingBreath else { return }
        let now = Date()
        manualTapTimestamps.append(now)
        if manualTapTimestamps.count > 4 { manualTapTimestamps.removeFirst() }
        guard manualTapTimestamps.count >= 2 else { return }

        var intervals: [Double] = []
        for i in 1..<manualTapTimestamps.count {
            intervals.append(manualTapTimestamps[i].timeIntervalSince(manualTapTimestamps[i - 1]))
        }
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard avgInterval > 0.8 && avgInterval < 15 else { return }

        applyDetectedBreath(period: avgInterval, bpm: 60.0 / avgInterval)
    }

    private func updateParams(_ mutate: (inout RenderParams) -> Void) {
        paramLock.lock()
        mutate(&params)
        paramLock.unlock()
    }

    // MARK: - Synthesis

    private func render(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        paramLock.lock()
        let p = params
        paramLock.unlock()

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

        for frame in 0..<Int(frameCount) {
            // Slow LFO drives the filter sweep ("movement").
            let lfoFreq = 0.02 + p.movement * 0.35
            lfoPhase += lfoFreq / sampleRate
            if lfoPhase > 1 { lfoPhase -= 1 }
            let lfo = sin(2 * Double.pi * lfoPhase)

            // Breathing amplitude envelope — rate/depth come from the session.
            breathPhase += p.breathRate / sampleRate
            if breathPhase > 1 { breathPhase -= 1 }
            let breath = 1.0 - p.breathDepth * 0.5 + p.breathDepth * 0.5 * sin(2 * Double.pi * breathPhase)

            // Pink-ish noise (Paul Kellet's approximation) — the raw material every
            // texture below is carved out of.
            let white = Double.random(in: -1...1)
            pinkState[0] = 0.99886 * pinkState[0] + white * 0.0555179
            pinkState[1] = 0.99332 * pinkState[1] + white * 0.0750759
            pinkState[2] = 0.96900 * pinkState[2] + white * 0.1538520
            pinkState[3] = 0.86650 * pinkState[3] + white * 0.3104856
            pinkState[4] = 0.55000 * pinkState[4] + white * 0.5329522
            pinkState[5] = -0.7616 * pinkState[5] - white * 0.0168980
            let pink = (pinkState[0] + pinkState[1] + pinkState[2] + pinkState[3] + pinkState[4] + pinkState[5] + pinkState[6] + white * 0.5362) * 0.11
            pinkState[6] = white * 0.115926

            // Ocean's wave envelope: a slow, asymmetric swell — a quick-ish rise to the
            // crest, a longer recede — rather than a plain sine, so it reads as water
            // washing in and out instead of a wobble.
            waveLfoPhase += (0.045 + p.movement * 0.035) / sampleRate
            if waveLfoPhase > 1 { waveLfoPhase -= 1 }
            let waveRaw = sin(2 * Double.pi * waveLfoPhase)
            let waveShape = waveRaw >= 0 ? pow(waveRaw, 0.6) : -pow(-waveRaw, 1.6)
            let waveCrest = max(0, waveShape)

            let dt = 1.0 / sampleRate

            // Two noise bands from the same pink-noise source: "air" is the higher,
            // breathier band (rain hiss / wind whistle / sea foam); "rumble" is a slow,
            // low undertone (distant thunder-less weight / surf body). Each atmosphere
            // blends and sweeps these completely differently below.
            let sweepDepth: Double
            switch p.atmosphere {
            case .wind: sweepDepth = 700.0 + p.movement * 1700.0
            case .ocean: sweepDepth = 150.0 + p.movement * 300.0
            case .rain: sweepDepth = 40.0 + p.movement * 80.0
            case .birds: sweepDepth = 60.0 + p.movement * 120.0
            }
            let oceanFoamLift = p.atmosphere == .ocean ? waveCrest * 900.0 : 0
            let airCutoff = max(80.0, 900.0 + p.brightness * 2200.0 + lfo * sweepDepth + oceanFoamLift)
            let airAlpha = dt / (1.0 / (2 * Double.pi * airCutoff) + dt)
            noiseFilterState += airAlpha * (pink - noiseFilterState)

            let rumbleCutoff = 50.0 + p.brightness * 140.0
            let rumbleAlpha = dt / (1.0 / (2 * Double.pi * rumbleCutoff) + dt)
            noiseLowState += rumbleAlpha * (pink - noiseLowState)

            var noiseMix = 0.6
            var airWeight = 1.0
            var rumbleWeight = 0.0
            var envelopeMultiplier = 1.0
            switch p.atmosphere {
            case .rain:
                // A quieter, thinner hiss bed than before — the earlier level was
                // loud and low-heavy enough on its own to read as surf/waves. Kept
                // deliberately restrained so the droplets below (not this bed) are
                // what identifies the sound as rain.
                noiseMix = 0.32 + p.texture * 0.22
                airWeight = 0.8
                rumbleWeight = 0.03
            case .wind:
                // Wide filter sweep (see sweepDepth above) plus body from the rumble
                // band and a slow gust — a whistling, gusting wind, not a steady wash.
                noiseMix = 0.6 + p.texture * 0.4
                airWeight = 0.75
                rumbleWeight = 0.55
                gustPhase += (0.03 + p.movement * 0.12) / sampleRate
                if gustPhase > 1 { gustPhase -= 1 }
                envelopeMultiplier = 0.75 + 0.25 * sin(2 * Double.pi * gustPhase)
            case .ocean:
                // Rumble-heavy body (the water) with the air band brightening right at
                // the wave's crest (foam), the whole thing swelling with waveShape.
                noiseMix = 0.6 + p.texture * 0.3
                airWeight = 0.3 + waveCrest * 0.7
                rumbleWeight = 0.9
                envelopeMultiplier = 0.5 + 0.5 * waveShape
            case .birds:
                // A near-silent, still-air bed so the chirps (below) are the feature,
                // not competing texture.
                noiseMix = 0.2 + p.texture * 0.15
                airWeight = 0.45
                rumbleWeight = 0.02
            }
            let noiseSignal = (noiseFilterState * airWeight + noiseLowState * rumbleWeight) * envelopeMultiplier

            // Sparse rain droplets: short, band-limited noise bursts at randomized
            // intervals — the transient detail that makes rain read as rain, not hiss.
            // Raw full-spectrum noise jumping straight to peak amplitude is a click
            // (hail on glass); running it through a damped lowpass with a short fade-in
            // rounds it into something closer to an actual droplet.
            var rainDrop = 0.0
            if p.atmosphere == .rain {
                if rainDropSamplesRemaining > 0 {
                    let progress = 1.0 - Double(rainDropSamplesRemaining) / Double(max(rainDropTotalSamples, 1))
                    let decay = Double(rainDropSamplesRemaining) / Double(max(rainDropTotalSamples, 1))
                    let attack = min(1.0, progress / 0.15)
                    // Brighter than the hiss bed's cutoff (~900-3100Hz) so each drop
                    // still snaps through as a distinct tick rather than blending into
                    // the bed underneath it.
                    let dropCutoff = 3200.0
                    let dropAlpha = dt / (1.0 / (2 * Double.pi * dropCutoff) + dt)
                    dropFilterState += dropAlpha * (Double.random(in: -1...1) - dropFilterState)
                    rainDrop = dropFilterState * decay * decay * attack
                    rainDropSamplesRemaining -= 1
                } else {
                    samplesUntilNextDrop -= 1
                    if samplesUntilNextDrop <= 0 {
                        // Shorter, more frequent drops than before — a constant,
                        // overlapping patter reads as rain; the old wider/sparser
                        // spacing left long silent gaps where only the (louder) hiss
                        // bed was audible, which is what made it sound like waves.
                        rainDropTotalSamples = Int(Double.random(in: 0.035...0.08) * sampleRate)
                        rainDropSamplesRemaining = rainDropTotalSamples
                        samplesUntilNextDrop = Int(Double.random(in: 0.02...0.12) * sampleRate)
                    }
                }
            }

            // Bird chirps: short frequency-swept tone bursts at randomized, sparse
            // intervals, so it reads as occasional birdsong rather than a synth loop.
            var birdSample = 0.0
            if p.atmosphere == .birds {
                if chirpSamplesRemaining > 0 {
                    let progress = 1.0 - Double(chirpSamplesRemaining) / Double(max(chirpTotalSamples, 1))
                    let freq = chirpFrequencyStart + chirpFrequencySweep * sin(progress * Double.pi)
                    chirpPhaseAccum += freq / sampleRate
                    if chirpPhaseAccum > 1 { chirpPhaseAccum -= 1 }
                    let envelope = sin(progress * Double.pi)
                    birdSample = sin(2 * Double.pi * chirpPhaseAccum) * envelope
                    chirpSamplesRemaining -= 1
                } else {
                    samplesUntilNextChirp -= 1
                    if samplesUntilNextChirp <= 0 {
                        chirpFrequencyStart = Double.random(in: 2200...3800)
                        chirpFrequencySweep = Double.random(in: 400...1200)
                        chirpTotalSamples = Int(Double.random(in: 0.12...0.22) * sampleRate)
                        chirpSamplesRemaining = chirpTotalSamples
                        chirpPhaseAccum = 0
                        samplesUntilNextChirp = Int(Double.random(in: 1.5...4.5) * sampleRate)
                    }
                }
            }

            var sample = noiseSignal * noiseMix * 1.8
            sample += rainDrop * 0.42
            sample += birdSample * 0.32
            sample *= breath

            // Fade toward the play/pause target — slow rise (~2s) so sound turning on
            // doesn't startle, fast fall (~200ms) so muting feels instant when wanted.
            let fadeAlpha = p.fadeTarget > fadeGain ? 0.00006 : 0.0006
            fadeGain += (p.fadeTarget - fadeGain) * fadeAlpha
            sample *= fadeGain * 0.3
            sample = tanh(sample)

            for buffer in buffers {
                let out = buffer.mData!.assumingMemoryBound(to: Float.self)
                out[frame] = Float(sample)
            }
        }

        return noErr
    }
}
