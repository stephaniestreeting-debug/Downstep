//
//  ContentView.swift
//  Downstep
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        BreathFollowView()
            .tint(Aura.Color.sage)
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioManager())
}
