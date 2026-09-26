//
//  BreathFollowView.swift
//  Downstep
//
//  The whole app is this one screen: pick a mood, begin, and watch the visual
//  reflect your actual breathing — settling as you slow down, with a gentle
//  nudge if it stays fast. No session picker, no fixed timer.
//

import SwiftUI

struct BreathFollowView: View {
    @EnvironmentObject private var audio: AudioManager
    @State private var showSynthesis = false

    private var isReady: Bool {
        !audio.isPlaying && audio.breathSummary == nil
    }

    /// 0...1 — how far the current pace is from calm, driving the visual's distortion.
    private var agitation: Double {
        guard let bpm = audio.currentBPM else { return 0 }
        let calmBPM = 10.0
        let fastBPM = 22.0
        return max(0, min(1, (bpm - calmBPM) / (fastBPM - calmBPM)))
    }

    var body: some View {
        ZStack {
            AuraBackground(imageName: audio.preferredTheme.backgroundImage)

            // A GeometryReader + ScrollView with a minHeight floor keeps the old
            // vertically-centered feel when everything fits, but lets the page
            // scroll instead of crushing its two Spacers to zero (which used to
            // jam the status text straight into "Make it yours" the moment that
            // section grew past what a given screen height had room for).
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header

                        Spacer(minLength: 20)

                        // Once a session actually ends (summary produced), always fall back
                        // to the plain orb as ambient backdrop — the drag track's own
                        // instructions ("drag up slowly...") are actively wrong to show
                        // once there's nothing left to drag for.
                        if audio.isManualModeChosen && !isReady && audio.breathSummary == nil {
                            // Prefer the de-escalation target over the raw current pace: once
                            // guidance is active, the drag's "too fast" warning should coach
                            // toward where the curve wants them next, not just describe
                            // whatever speed they already happen to be dragging at.
                            GroundingTrackView(referenceBPM: audio.guidanceTargetBPM ?? audio.currentBPM) {
                                audio.registerRhythmSignal()
                            }
                            .frame(height: 260)
                        } else {
                            // Idle on the Ready screen, the orb is purely decorative — no
                            // live breath feedback to show yet — so it can afford to be
                            // smaller there, freeing up room for "Make it yours" to breathe
                            // without pushing the whole page into more scrolling than it needs.
                            let orbSize: CGFloat = isReady ? 200 : 260
                            BreathVisualView(state: audio.breathFollowState, liveLevel: audio.liveBreathLevel, agitation: agitation, targetBPM: audio.guidanceTargetBPM)
                                .frame(width: orbSize, height: orbSize)
                        }

                        statusText
                            .padding(.top, 26)
                            .frame(minHeight: 40)

                        Spacer(minLength: 28)

                        if let summary = audio.breathSummary {
                            BreathSummaryView(
                                summary: summary,
                                history: audio.bpmHistory,
                                elapsed: audio.elapsed,
                                timeToCalmSeconds: audio.timeToCalmSeconds,
                                stepCount: audio.stepCount,
                                startBPM: audio.startBPM,
                                lowestGuidedBPM: audio.lowestGuidedBPM
                            ) {
                                audio.stop()
                            }
                        } else if isReady {
                            readyControls
                        } else {
                            activeControls
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSynthesis) {
            SynthesisControlsView()
                .environmentObject(audio)
                .presentationDetents([.fraction(0.3)])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("DOWNSTEP")
                .auraDisplayFont(22)
                .tracking(4)
                .foregroundStyle(Aura.Color.cream)
            AuraLabel(text: "Breathe. It listens.", size: 12, color: Aura.Color.mist.opacity(0.7))
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusText: some View {
        // The Ready screen always gets the plain idle prompt, never leftover
        // session text — `breathFollowState` itself doesn't always reset the
        // instant a session ends (e.g. `finish()` can leave it at `.following`
        // if no summary was produced), so this checks readiness first rather
        // than trusting breathFollowState alone.
        if isReady {
            AuraLabel(text: "Tap begin when you're ready", size: 13, color: Aura.Color.mist.opacity(0.7), tracking: 1, weight: .semibold)
        } else {
            activeStatusText
        }
    }

    @ViewBuilder
    private var activeStatusText: some View {
        switch audio.breathFollowState {
        case .idle:
            EmptyView()
        case .calibrating:
            // In manual mode there's no mic to fall back from — showing "tap
            // here instead" while already on the touch track is a redundant
            // leftover of a check meant only for the reactive mic-loss case.
            if audio.shouldOfferTapFallback && !audio.isManualModeChosen {
                tapInsteadLink
            } else if !audio.isManualModeChosen {
                AuraLabel(text: "Finding your rhythm\u{2026}", size: 12, color: Aura.Color.cream.opacity(0.85), tracking: 1.5)
            }
        case .following:
            VStack(spacing: 8) {
                if let bpm = audio.currentBPM {
                    Text("\(Int(bpm.rounded())) breaths / min")
                        .auraFont(13, weight: .semibold)
                        .tracking(1)
                        .foregroundStyle(Aura.Color.cream)
                }
                if let guidance = audio.guidanceMessage {
                    Text(guidance)
                        .auraDisplayFont(17)
                        .foregroundStyle(Aura.Color.amber)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.6), value: guidance)
                } else if let encouragement = audio.encouragementMessage {
                    Text(encouragement)
                        .auraDisplayFont(17)
                        .foregroundStyle(Aura.Color.sage)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.6), value: encouragement)
                }
            }
        case .lost:
            // Same reasoning as `.calibrating` above: no mic to lose in touch mode,
            // so neither the "switch to touch" offer nor "couldn't hear you" applies.
            if audio.shouldOfferTapFallback && !audio.isManualModeChosen {
                tapInsteadLink
            } else if !audio.isManualModeChosen {
                AuraLabel(text: "Couldn't hear you \u{2014} guiding instead", size: 12, color: Aura.Color.amber.opacity(0.85), tracking: 1)
            }
        }
    }

    private var tapInsteadLink: some View {
        // Offered, never applied on its own — the mic-loss timeout only ever
        // shows this hint; the drag track appears when (and only when) it's
        // actually tapped.
        Button {
            audio.confirmManualFallback()
        } label: {
            Text("STRUGGLING TO HEAR YOU — TAP TO SWITCH TO TOUCH")
                .auraFont(12, weight: .semibold)
                .tracking(1)
                .foregroundStyle(Aura.Color.mist.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
    }

    private var readyControls: some View {
        VStack(spacing: 22) {
            makeItYours

            Button {
                switch audio.preferredInputMode {
                case .mic: audio.beginSession(audio.preferredTheme)
                case .touch: audio.beginManualSession(audio.preferredTheme)
                }
            } label: {
                Text("BEGIN")
                    .auraFont(13, weight: .semibold)
                    .tracking(2)
                    .foregroundStyle(Aura.Color.void)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(Aura.Color.cream))
            }
            .buttonStyle(.plain)

            Text("From the makers of Life Forecast, EchoSink & Pocket Anchor")
                .auraFont(11, weight: .medium)
                .foregroundStyle(Aura.Color.mist.opacity(0.4))
        }
    }

    /// Every choice that shapes a session, decided upfront instead of assumed
    /// or buried in a settings sheet — each one remembers its last value as
    /// the default next time, but is always visible and always changeable.
    private var makeItYours: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                AuraLabel(text: "Make it yours", size: 13, color: Aura.Color.cream, tracking: 1.5)
                Text("Remembers your choices next time.")
                    .auraFont(11, weight: .medium)
                    .foregroundStyle(Aura.Color.mist.opacity(0.6))
            }

            choiceRow(label: "Input", subtitle: inputSubtitle) {
                AuraPillSelector(options: BreathInputMode.allCases, selection: $audio.preferredInputMode) { $0.rawValue }
            }

            choiceRow(label: "Sound", subtitle: "Plays under everything else") {
                AuraPillSelector(options: SoundPreference.allCases, selection: soundBinding) { $0.rawValue }
            }

            choiceRow(label: "Atmosphere", subtitle: "The background sound you hear") {
                AuraPillSelector(options: AtmosphereStyle.allCases, selection: $audio.atmosphereStyle) { $0.rawValue }
            }

            choiceRow(label: "Backdrop", subtitle: "Sets the mood, not the mechanic") {
                themePicker
            }
        }
    }

    private var soundBinding: Binding<SoundPreference> {
        Binding(
            get: { audio.soundEnabled ? .on : .off },
            set: { audio.soundEnabled = $0 == .on }
        )
    }

    /// Proximity only matters for the mic — the touch track has no equivalent
    /// concern, so the tip only shows up when it's actually relevant. Deliberately
    /// doesn't say "hold it close" — the whole point is watching the screen react
    /// to your breathing, so pressing the phone against your face to be heard
    /// would defeat the actual feature. Propped up nearby is enough; headphones
    /// solve distance entirely since the mic is then at your ear regardless of
    /// where the phone sits.
    private var inputSubtitle: String {
        switch audio.preferredInputMode {
        case .mic: "Works best propped nearby — headphones help it hear you too"
        case .touch: "How it follows your breathing"
        }
    }

    private func choiceRow<Content: View>(label: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                AuraLabel(text: label, size: 10, color: Aura.Color.sage, tracking: 1.2, weight: .semibold)
                Text(subtitle)
                    .auraFont(11, weight: .medium)
                    .foregroundStyle(Aura.Color.mist.opacity(0.6))
            }
            content()
        }
    }

    private var themePicker: some View {
        HStack(spacing: 14) {
            ForEach(BreathTheme.all) { theme in
                Button {
                    audio.preferredTheme = theme
                } label: {
                    VStack(spacing: 8) {
                        Image(theme.backgroundImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .overlay(
                                Circle().strokeBorder(
                                    audio.preferredTheme.id == theme.id ? Aura.Color.sage : Aura.Color.hairline,
                                    lineWidth: audio.preferredTheme.id == theme.id ? 2 : 1
                                )
                            )
                        Text(theme.name)
                            .auraFont(11, weight: .semibold)
                            .foregroundStyle(audio.preferredTheme.id == theme.id ? Aura.Color.cream : Aura.Color.mist.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activeControls: some View {
        HStack {
            Button {
                audio.soundEnabled.toggle()
            } label: {
                Image(systemName: audio.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Aura.Color.cream)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Aura.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if audio.soundEnabled {
                AuraIconButton(systemName: "slider.horizontal.3") { showSynthesis = true }
            }

            Spacer()

            Button {
                audio.finish()
            } label: {
                Text("I'M DONE")
                    .auraFont(12, weight: .semibold)
                    .tracking(1.5)
                    .foregroundStyle(Aura.Color.cream)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 22)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(Aura.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    BreathFollowView()
        .environmentObject(AudioManager())
}
