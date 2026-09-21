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
    @State private var selectedTheme: BreathTheme = .breathe
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
            AuraBackground(imageName: selectedTheme.backgroundImage)

            VStack(spacing: 0) {
                header

                Spacer(minLength: 0)

                if (audio.shouldOfferTapFallback || audio.isManualModeChosen) && !isReady {
                    // Prefer the de-escalation target over the raw current pace: once
                    // guidance is active, the drag's "too fast" warning should coach
                    // toward where the curve wants them next, not just describe
                    // whatever speed they already happen to be dragging at.
                    GroundingTrackView(referenceBPM: audio.guidanceTargetBPM ?? audio.currentBPM) {
                        audio.registerRhythmSignal()
                    }
                    .frame(height: 260)
                } else {
                    BreathVisualView(state: audio.breathFollowState, liveLevel: audio.liveBreathLevel, agitation: agitation, targetBPM: audio.guidanceTargetBPM)
                        .frame(width: 260, height: 260)
                }

                statusText
                    .padding(.top, 26)
                    .frame(minHeight: 40)

                Spacer(minLength: 0)

                if let summary = audio.breathSummary {
                    BreathSummaryView(
                        summary: summary,
                        history: audio.bpmHistory,
                        elapsed: audio.elapsed,
                        timeToCalmSeconds: audio.timeToCalmSeconds,
                        timeToCalmIsBest: audio.timeToCalmIsBest,
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
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSynthesis) {
            SynthesisControlsView()
                .environmentObject(audio)
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("DOWNSTEP")
                .font(Aura.Font.display(22))
                .tracking(4)
                .foregroundStyle(Aura.Color.cream)
            AuraLabel(text: "Breathe. It listens.", size: 11, color: Aura.Color.mist.opacity(0.7))
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusText: some View {
        switch audio.breathFollowState {
        case .idle:
            if isReady {
                AuraLabel(text: "Tap begin when you're ready", size: 12, color: Aura.Color.mist.opacity(0.6), tracking: 1)
            }
        case .calibrating:
            if audio.shouldOfferTapFallback {
                tapInsteadLink
            } else {
                AuraLabel(text: "Finding your rhythm\u{2026}", size: 12, color: Aura.Color.cream.opacity(0.85), tracking: 1.5)
            }
        case .following:
            VStack(spacing: 8) {
                if let bpm = audio.currentBPM {
                    Text("\(Int(bpm.rounded())) breaths / min")
                        .font(Aura.Font.label(13, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Aura.Color.cream)
                }
                if let guidance = audio.guidanceMessage {
                    Text(guidance)
                        .font(Aura.Font.display(17))
                        .foregroundStyle(Aura.Color.amber)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.6), value: guidance)
                } else if let encouragement = audio.encouragementMessage {
                    Text(encouragement)
                        .font(Aura.Font.display(17))
                        .foregroundStyle(Aura.Color.sage)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.6), value: encouragement)
                }
            }
        case .lost:
            if audio.shouldOfferTapFallback {
                tapInsteadLink
            } else {
                AuraLabel(text: "Couldn't hear you \u{2014} guiding instead", size: 12, color: Aura.Color.amber.opacity(0.85), tracking: 1)
            }
        }
    }

    private var tapInsteadLink: some View {
        Button {
            audio.registerRhythmSignal()
        } label: {
            Text("OR TAP HERE INSTEAD")
                .font(Aura.Font.label(11, weight: .medium))
                .tracking(1)
                .foregroundStyle(Aura.Color.mist.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    private var readyControls: some View {
        VStack(spacing: 24) {
            themePicker

            Button {
                audio.beginSession(selectedTheme)
            } label: {
                Text("BEGIN")
                    .font(Aura.Font.label(13, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Aura.Color.void)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(Aura.Color.cream))
            }
            .buttonStyle(.plain)

            Button {
                audio.beginManualSession(selectedTheme)
            } label: {
                Text("IN A NOISY PLACE? TRACK BY TOUCH INSTEAD")
                    .font(Aura.Font.label(10, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Aura.Color.mist.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
    }

    private var themePicker: some View {
        HStack(spacing: 14) {
            ForEach(BreathTheme.all) { theme in
                Button {
                    selectedTheme = theme
                } label: {
                    VStack(spacing: 8) {
                        Image(theme.backgroundImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(
                                Circle().strokeBorder(
                                    selectedTheme.id == theme.id ? Aura.Color.sage : Aura.Color.hairline,
                                    lineWidth: selectedTheme.id == theme.id ? 2 : 1
                                )
                            )
                        Text(theme.name)
                            .font(Aura.Font.label(10, weight: .medium))
                            .foregroundStyle(selectedTheme.id == theme.id ? Aura.Color.cream : Aura.Color.mist.opacity(0.6))
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
                    .font(Aura.Font.label(12, weight: .semibold))
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
