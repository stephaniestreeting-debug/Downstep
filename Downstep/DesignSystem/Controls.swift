//
//  Controls.swift
//  Downstep
//

import SwiftUI

/// A row of equal-weight capsule choices — used for every "make it yours"
/// upfront choice (input, sound, atmosphere) so they all read as peers.
struct AuraPillSelector<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = option }
                } label: {
                    Text(label(option).uppercased())
                        .font(Aura.Font.label(11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(selection == option ? Aura.Color.void : Aura.Color.mist)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(selection == option ? Aura.Color.sage : Color.white.opacity(0.06))
                        )
                        .overlay(
                            Capsule().strokeBorder(Aura.Color.hairline, lineWidth: selection == option ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AuraIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(Aura.Color.cream)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Aura.Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
