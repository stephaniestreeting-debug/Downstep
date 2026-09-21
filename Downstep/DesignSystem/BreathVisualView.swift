//
//  BreathVisualView.swift
//  Downstep
//
//  The centerpiece of the app. Two things drive it, both fed by the mic:
//  `displayLevel` (0...1) is the moment-to-moment breath envelope — the shape
//  pulses with it directly, in real time, so the connection to your actual
//  breathing is immediate rather than implied. `agitation` (0...1) reflects how
//  far the current pace is from calm — at 0 the form is a smooth, still circle;
//  as it rises the edge grows jagged and restless, and the color leans from calm
//  sage toward alert amber. Slowing down visibly un-does the distortion.
//

import SwiftUI

struct BreathVisualView: View {
    var state: BreathFollowState
    /// Live mic envelope, 0...1 — only meaningful (and only used) while `state == .following`.
    var liveLevel: Double
    /// How far the current pace is from calm, 0...1 — only meaningful while `state == .following`.
    var agitation: Double
    /// A gentle target pace (breaths/min) to show as a faint outer ring to sync to,
    /// non-nil only while guidance is active. Not a rigid metronome — just something
    /// concrete to aim for instead of only being told to slow down.
    var targetBPM: Double?

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            // Idle/calibrating/lost all animate off the clock so the visual is always
            // alive even before (or without) a live mic signal; only "following" hands
            // control to the actual breath envelope.
            let level: Double = Self.displayLevel(for: state, time: t, liveLevel: liveLevel)
            let calm: Double = state == .following ? max(0, min(1, agitation)) : 0

            Canvas { canvasContext, size in
                let centerX: Double = Double(size.width) / 2
                let centerY: Double = Double(size.height) / 2
                let center = CGPoint(x: centerX, y: centerY)
                let baseRadius: Double = Double(min(size.width, size.height)) / 2 * 0.62
                let pulseRadius: Double = baseRadius * (0.9 + level * 0.22)
                let jitterAmplitude: Double = baseRadius * 0.28 * calm

                var path = Path()
                let steps = 96
                for i in 0...steps {
                    let angle: Double = Double(i) / Double(steps) * 2 * .pi
                    // A few summed, slowly-drifting sine harmonics make the jitter feel
                    // organic rather than a single obvious wobble.
                    let wave1: Double = sin(angle * 5 + t * 3.1) * 0.5
                    let wave2: Double = sin(angle * 9 - t * 2.3) * 0.3
                    let wave3: Double = sin(angle * 13 + t * 4.7) * 0.2
                    let jitter: Double = jitterAmplitude * (wave1 + wave2 + wave3)
                    let radius: Double = pulseRadius + jitter
                    let x: Double = centerX + cos(angle) * radius
                    let y: Double = centerY + sin(angle) * radius
                    let point = CGPoint(x: x, y: y)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()

                let fillGradient = Gradient(colors: [
                    Aura.Color.amber.opacity(0.55 + calm * 0.25),
                    Aura.Color.sage.opacity(0.5 - calm * 0.2),
                    Aura.Color.sageDeep.opacity(0.35)
                ])

                canvasContext.fill(
                    path,
                    with: .radialGradient(
                        fillGradient,
                        center: center,
                        startRadius: 0,
                        endRadius: CGFloat(pulseRadius + jitterAmplitude)
                    )
                )

                canvasContext.stroke(
                    path,
                    with: .color(Aura.Color.cream.opacity(0.4 + level * 0.3)),
                    lineWidth: 1.2
                )

                // Soft outer glow that breathes with the live level.
                let glowOuterRadius: Double = pulseRadius + 30
                var glowPath = Path()
                glowPath.addEllipse(in: CGRect(
                    x: centerX - glowOuterRadius,
                    y: centerY - glowOuterRadius,
                    width: glowOuterRadius * 2,
                    height: glowOuterRadius * 2
                ))
                canvasContext.opacity = 0.18 + level * 0.15
                canvasContext.fill(glowPath, with: .radialGradient(
                    Gradient(colors: [Aura.Color.amber.opacity(0.5), .clear]),
                    center: center,
                    startRadius: CGFloat(pulseRadius * 0.5),
                    endRadius: CGFloat(pulseRadius + 40)
                ))
                canvasContext.opacity = 1

                // A faint pacing ring to sync to when guidance is active — pulses at
                // the gentle target rate, wider than the main shape so it reads as a
                // guide to grow into rather than a cage around it.
                //
                // The de-escalation curve behind `targetBPM` moves in fixed 1.2bpm
                // steps, not a smooth glide — so the ring's baseline size reads
                // straight off the current value with no easing applied here. A step
                // in the curve shows up as a step in the ring on the very next frame,
                // matching what's actually happening (and the app's name) instead of
                // implying a continuous slide toward calm.
                if let targetBPM {
                    let targetHz = targetBPM / 60.0
                    let ringPulse = 0.5 + 0.5 * sin(2 * Double.pi * t * targetHz)
                    let calmFloor = 6.0
                    let calmCeiling = 30.0
                    let calmProgress = max(0, min(1, (calmCeiling - targetBPM) / (calmCeiling - calmFloor)))
                    let ringBase = baseRadius * (1.30 - calmProgress * 0.20)
                    let ringRadius = ringBase + baseRadius * ringPulse * 0.10

                    var ringPath = Path()
                    ringPath.addEllipse(in: CGRect(
                        x: centerX - ringRadius,
                        y: centerY - ringRadius,
                        width: ringRadius * 2,
                        height: ringRadius * 2
                    ))
                    canvasContext.stroke(ringPath, with: .color(Aura.Color.amber.opacity(0.45)), lineWidth: 1.5)

                    // Short radial ticks around the ring — a literal stepped dial
                    // rather than a plain circle.
                    let notchCount = 24
                    for i in 0..<notchCount {
                        let angle: Double = Double(i) / Double(notchCount) * 2 * .pi
                        let inner: Double = ringRadius - 4
                        let outer: Double = ringRadius + 4
                        let x1: Double = centerX + cos(angle) * inner
                        let y1: Double = centerY + sin(angle) * inner
                        let x2: Double = centerX + cos(angle) * outer
                        let y2: Double = centerY + sin(angle) * outer
                        var notchPath = Path()
                        notchPath.move(to: CGPoint(x: x1, y: y1))
                        notchPath.addLine(to: CGPoint(x: x2, y: y2))
                        canvasContext.stroke(notchPath, with: .color(Aura.Color.amber.opacity(0.3)), lineWidth: 1)
                    }
                }
            }
        }
    }

    private static func displayLevel(for state: BreathFollowState, time: Double, liveLevel: Double) -> Double {
        switch state {
        case .idle: return 0.5 + 0.5 * sin(time * 0.25)
        case .calibrating: return 0.5 + 0.5 * sin(time * 0.45)
        case .following: return max(0, min(1, liveLevel))
        case .lost: return 0.5 + 0.5 * sin(time * 0.3)
        }
    }
}
