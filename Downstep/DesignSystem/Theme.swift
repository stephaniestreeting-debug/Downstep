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

    enum Tracking {
        static let wide: CGFloat = 3.5
        static let mid: CGFloat = 1.6
    }
}

/// A `.font(.system(size:))` call is pinned to that exact point size forever —
/// someone using iOS's own Larger Text accessibility setting (Settings ›
/// Accessibility › Display & Text Size) sees no difference at all, unlike
/// system text styles (`.body`, `.caption`, …) which scale automatically.
/// `@ScaledMetric` is SwiftUI's way to get that same scaling behavior on a
/// custom size instead of one of the fixed built-in styles, but it only works
/// as a property on a `View`/`ViewModifier` (it needs the environment), so it
/// can't live on a plain static helper — hence this modifier instead of a
/// function on `Aura.Font`.
private struct ScaledAuraFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let weight: SwiftUI.Font.Weight
    private let design: SwiftUI.Font.Design

    init(size: CGFloat, weight: SwiftUI.Font.Weight, design: SwiftUI.Font.Design) {
        self._scaledSize = ScaledMetric(wrappedValue: size)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight, design: design))
    }
}

extension View {
    /// Aura's small-caption/UI text — scales with the system's text-size setting.
    func auraFont(_ size: CGFloat, weight: SwiftUI.Font.Weight = .medium) -> some View {
        modifier(ScaledAuraFont(size: size, weight: weight, design: .default))
    }

    /// Aura's serif display text (session titles, headline moments) — same
    /// Dynamic Type scaling as `auraFont`, just the light serif treatment.
    func auraDisplayFont(_ size: CGFloat) -> some View {
        modifier(ScaledAuraFont(size: size, weight: .light, design: .serif))
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
            .auraFont(size, weight: weight)
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
