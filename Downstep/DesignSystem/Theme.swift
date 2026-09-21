//
//  Theme.swift
//  Downstep
//

import SwiftUI

enum Aura {
    enum Color {
        static let void = SwiftUI.Color(red: 0.02, green: 0.03, blue: 0.03)
        static let ink = SwiftUI.Color(red: 0.05, green: 0.07, blue: 0.06)
        static let sage = SwiftUI.Color(red: 0.55, green: 0.70, blue: 0.62)
        static let sageDeep = SwiftUI.Color(red: 0.31, green: 0.45, blue: 0.39)
        static let amber = SwiftUI.Color(red: 0.85, green: 0.66, blue: 0.38)
        static let amberDeep = SwiftUI.Color(red: 0.62, green: 0.45, blue: 0.24)
        static let mist = SwiftUI.Color(red: 0.78, green: 0.82, blue: 0.80)
        static let cream = SwiftUI.Color(red: 0.94, green: 0.94, blue: 0.90)
        static let hairline = SwiftUI.Color.white.opacity(0.14)
    }

    enum Font {
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .light, design: .serif)
        }
        static func label(_ size: CGFloat = 12, weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .default)
        }
    }

    enum Tracking {
        static let wide: CGFloat = 3.5
        static let mid: CGFloat = 1.6
    }
}

/// Wide-tracked, uppercase small caption used throughout for eyebrow labels and captions.
struct AuraLabel: View {
    let text: String
    var size: CGFloat = 12
    var color: Color = Aura.Color.mist
    var tracking: CGFloat = Aura.Tracking.wide
    var weight: Font.Weight = .medium

    var body: some View {
        Text(text.uppercased())
            .font(Aura.Font.label(size, weight: weight))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

struct AuraBackground: View {
    let imageName: String

    var body: some View {
        GeometryReader { proxy in
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay(
                    LinearGradient(
                        colors: [
                            Aura.Color.void.opacity(0.35),
                            Aura.Color.void.opacity(0.55),
                            Aura.Color.void.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipped()
        }
        .ignoresSafeArea()
    }
}
