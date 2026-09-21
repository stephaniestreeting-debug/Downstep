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
        }
    }
}
