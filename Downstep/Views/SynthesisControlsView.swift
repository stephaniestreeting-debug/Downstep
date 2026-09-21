//
//  SynthesisControlsView.swift
//  Downstep
//

import SwiftUI

struct SynthesisControlsView: View {
    @EnvironmentObject private var audio: AudioManager

    var body: some View {
        ZStack {
            Aura.Color.void.ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("Real-Time Audio\nSynthesis")
                        .multilineTextAlignment(.center)
                        .font(Aura.Font.display(24))
                        .foregroundStyle(Aura.Color.cream)
                    AuraLabel(text: "Shaped by your moment", size: 11, color: Aura.Color.mist.opacity(0.65))
                }
                .padding(.top, 18)

                WaveformView(movement: audio.movementAmount, texture: audio.textureAmount)
                    .frame(height: 90)
                    .padding(.horizontal, 8)

                AuraPillSelector(options: AtmosphereStyle.allCases, selection: $audio.atmosphereStyle) { $0.rawValue }

                VStack(spacing: 22) {
                    AuraSlider(title: "Atmosphere", value: $audio.atmosphereAmount)
                    AuraSlider(title: "Texture", value: $audio.textureAmount)
                    AuraSlider(title: "Movement", value: $audio.movementAmount)
                }
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
        }
    }
}

#Preview {
    SynthesisControlsView()
        .environmentObject(AudioManager())
}
