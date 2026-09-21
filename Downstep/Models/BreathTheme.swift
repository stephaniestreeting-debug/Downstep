//
//  BreathTheme.swift
//  Downstep
//

import Foundation

/// The nature-sound character selectable when sound is on. There is no synth
/// tone/hum in the mix — everything here is a generated nature texture.
enum AtmosphereStyle: String, CaseIterable, Identifiable, Hashable {
    case rain = "Rain"
    case wind = "Wind"
    case ocean = "Ocean"
    case birds = "Birds"

    var id: String { rawValue }
}

/// How a session follows breathing — chosen upfront on the Ready screen, not
/// assumed or silently switched mid-session.
enum BreathInputMode: String, CaseIterable, Identifiable, Hashable {
    case mic = "Listen with mic"
    case touch = "Track by touch"

    var id: String { rawValue }
}

/// Whether the generated nature-sound bed plays — a third upfront choice,
/// alongside input and atmosphere, rather than a toggle buried mid-session.
enum SoundPreference: String, CaseIterable, Identifiable, Hashable {
    case on = "Sound on"
    case off = "Silent"

    var id: String { rawValue }
}

/// A visual/mood theme for the single breath-following screen — background art,
/// a default nature-sound character (used only if sound is turned on), and the
/// paced breathing rate/depth used as a fallback if the mic loses the signal.
struct BreathTheme: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let backgroundImage: String
    let defaultAtmosphere: AtmosphereStyle

    /// Fallback paced rate/depth (Hz, 0...1) used only while the mic can't hear a
    /// clear breath signal — the mic-driven rate takes over the moment it can.
    let breathRate: Double
    let breathDepth: Double
    /// Baseline noise/texture mix, 0...1, before the user's Texture slider is applied.
    let baseTexture: Double
    /// Baseline filter brightness, 0...1 (higher = brighter/more open low-pass cutoff).
    let baseBrightness: Double
    let inhaleCue: String
    let exhaleCue: String

    static let breathe = BreathTheme(
        name: "Breathe",
        backgroundImage: "SunsetBackground",
        defaultAtmosphere: .rain,
        breathRate: 0.10,
        breathDepth: 0.55,
        baseTexture: 0.35,
        baseBrightness: 0.4,
        inhaleCue: "Breathe In",
        exhaleCue: "Breathe Out"
    )

    static let focus = BreathTheme(
        name: "Focus",
        backgroundImage: "CosmicBackground",
        defaultAtmosphere: .wind,
        breathRate: 0.05,
        breathDepth: 0.18,
        baseTexture: 0.4,
        baseBrightness: 0.5,
        inhaleCue: "Breathe In",
        exhaleCue: "Breathe Out"
    )

    static let letGo = BreathTheme(
        name: "Let Go",
        backgroundImage: "MistBackground 1",
        defaultAtmosphere: .ocean,
        breathRate: 0.035,
        breathDepth: 0.75,
        baseTexture: 0.45,
        baseBrightness: 0.3,
        inhaleCue: "Breathe In",
        exhaleCue: "Breathe Out"
    )

    static let all: [BreathTheme] = [.breathe, .focus, .letGo]

    /// Looked up by name for persistence — themes are re-created fresh each
    /// launch, so a saved UUID would never match; the name is what's stable.
    static func named(_ name: String?) -> BreathTheme {
        all.first { $0.name == name } ?? .breathe
    }
}
