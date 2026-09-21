//
//  WaveformView.swift
//  Downstep
//

import SwiftUI

/// A gently animated set of flowing lines used on the synthesis screen to give
/// a visual sense of the live-generated texture underneath the sliders.
struct WaveformView: View {
    var movement: Double
    var texture: Double

    private let lines: [(color: Color, amplitude: CGFloat, speed: Double, opacity: Double)] = [
        (Aura.Color.amber, 18, 0.6, 0.85),
        (Aura.Color.sage, 26, 0.4, 0.7),
        (Aura.Color.sageDeep, 14, 0.9, 0.5)
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvasContext, size in
                for (index, line) in lines.enumerated() {
                    var path = Path()
                    let speed = line.speed * (0.5 + movement)
                    let amplitude = line.amplitude * (0.6 + CGFloat(texture) * 0.8)
                    let frequency = 1.4 + Double(index) * 0.6

                    for x in stride(from: 0, through: size.width, by: 2) {
                        let progress = x / size.width
                        let y = size.height / 2
                            + sin(progress * .pi * frequency + t * speed + Double(index)) * amplitude
                            + sin(progress * .pi * frequency * 2.3 - t * speed * 0.7) * (amplitude * 0.25)
                        if x == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    canvasContext.stroke(
                        path,
                        with: .color(line.color.opacity(line.opacity)),
                        lineWidth: 1.4
                    )
                }
            }
        }
    }
}
