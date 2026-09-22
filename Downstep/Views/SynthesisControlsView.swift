//
//  SynthesisControlsView.swift
//  Downstep
//

import SwiftUI

struct SynthesisControlsView: View {
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Aura.Color.void.ignoresSafeArea()

            VStack(spacing: 10) {
                ZStack {
                    VStack(alignment: .leading, spacing: 2) {
                        AuraLabel(text: "Atmosphere", size: 12, color: Aura.Color.cream, tracking: 1.5)
                        Text("Change the background sound mid-session.")
                            .auraFont(11, weight: .regular)
                            .foregroundStyle(Aura.Color.mist.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Aura.Color.mist.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 14)

                AuraPillSelector(options: AtmosphereStyle.allCases, selection: $audio.atmosphereStyle) { $0.rawValue }

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
