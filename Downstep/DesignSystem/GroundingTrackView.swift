//
//  GroundingTrackView.swift
//  Downstep
//
//  A physical, mic-free fallback: drag a bubble up to breathe in, down to breathe
//  out. The physical task is itself grounding (a precise motor-cortex task pulls
//  attention out of a panic spiral), and dragging faster than the target pace
//  warms the bubble from calm sage toward amber — the same color language the
//  main breath visual already uses for "too fast" — as a gentle cue to ease up,
//  without any text needed. Each completed up-down cycle feeds the same tracking
//  pipeline mic/tap detection does.
//

import SwiftUI

struct GroundingTrackView: View {
    /// The best known current pace, used only to set the target drag speed for the
    /// color warning. Falls back to a calm reference pace when nothing is known yet.
    var referenceBPM: Double?
    var onCycleComplete: () -> Void

    private enum Phase { case inhale, exhale }

    @State private var phase: Phase = .inhale
    @State private var committedOffset: CGFloat = 0
    @State private var smoothedWarmth: Double = 0
    @GestureState private var dragTranslation: CGFloat = 0
    /// `.soft` is Apple's dull, rounded, lower-amplitude impact style — a low
    /// thud rather than a sharp tap, matching a breath's own weight.
    private let phaseHaptic = UIImpactFeedbackGenerator(style: .soft)

    private let trackHeight: CGFloat = 220
    private let bubbleSize: CGFloat = 52

    private var phaseSeconds: Double {
        let bpm = max(6, min(referenceBPM ?? 12, 30))
        return 30.0 / bpm
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(phase == .inhale ? "Drag up slowly to breathe in" : "Pull down gently to breathe out")
                .font(Aura.Font.label(12, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Aura.Color.mist.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(height: 30)
                .animation(.easeInOut(duration: 0.3), value: phase)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 6, height: trackHeight)

                Circle()
                    .fill(bubbleColor)
                    .frame(width: bubbleSize, height: bubbleSize)
                    .overlay(Circle().strokeBorder(Aura.Color.hairline, lineWidth: 1))
                    .shadow(color: bubbleColor.opacity(0.5), radius: 12)
                    .offset(y: clampedOffset(committedOffset + dragTranslation))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($dragTranslation) { value, state, _ in
                                state = value.translation.height
                            }
                            .onChanged { value in
                                updateWarmth(velocity: value.velocity.height)
                                // Evaluate phase transitions live, off the actual
                                // finger position — not just at gesture-end. A real
                                // breath is one continuous up-then-down motion with
                                // the finger never lifting, so waiting for the whole
                                // gesture to end before checking anything meant a
                                // normal drag never registered as a completed breath.
                                let liveOffset = clampedOffset(committedOffset + value.translation.height)
                                evaluatePhase(at: liveOffset)
                            }
                            .onEnded { value in
                                committedOffset = clampedOffset(committedOffset + value.translation.height)
                            }
                    )
            }
            .frame(height: trackHeight)
        }
    }

    private func clampedOffset(_ value: CGFloat) -> CGFloat {
        min(0, max(-trackHeight, value))
    }

    private var bubbleColor: Color {
        Aura.Color.sage.blended(with: Aura.Color.amber, amount: smoothedWarmth)
    }

    private func updateWarmth(velocity: Double) {
        let targetVelocity = Double(trackHeight) / phaseSeconds
        let ratio = targetVelocity > 0 ? abs(velocity) / targetVelocity : 0
        let excess = max(0, ratio - 1.0)
        let warmth = min(1, excess / 0.5)
        smoothedWarmth += (warmth - smoothedWarmth) * 0.2
    }

    /// Checked continuously against the live finger position. Deliberately never
    /// touches `committedOffset` mid-gesture — that stays fixed at the gesture's
    /// starting point so `committedOffset + dragTranslation` (translation is always
    /// relative to where THIS touch began) keeps tracking the finger smoothly, no
    /// matter how many phase flips happen within one continuous drag.
    private func evaluatePhase(at liveOffset: CGFloat) {
        switch phase {
        case .inhale:
            if liveOffset <= -trackHeight * 0.75 {
                phase = .exhale
                phaseHaptic.impactOccurred()
            }
        case .exhale:
            if liveOffset >= -trackHeight * 0.15 {
                phase = .inhale
                phaseHaptic.impactOccurred()
                onCycleComplete()
            }
        }
    }
}

private extension Color {
    /// Linearly blends two colors by RGB components — used for the drag track's
    /// calm-to-alert warming rather than a hard color swap.
    func blended(with other: Color, amount: Double) -> Color {
        let t = max(0, min(1, amount))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t)
        )
    }
}
