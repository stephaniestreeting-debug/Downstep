//
//  DownstepApp.swift
//  Downstep
//

import SwiftUI

@main
struct DownstepApp: App {
    @StateObject private var audio = AudioManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audio)
                .onOpenURL { url in
                    // The home-screen widget's whole surface is a "downstep://begin"
                    // link — every tap should count mid-panic, so this skips straight
                    // to a session instead of just bringing the Ready screen forward.
                    guard url.host == "begin", !audio.isPlaying, audio.breathSummary == nil else { return }
                    audio.beginSession(.breathe)
                }
        }
    }
}
