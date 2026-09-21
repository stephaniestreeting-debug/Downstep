//
//  Controls.swift
//  Downstep
//

import SwiftUI

struct AuraPillSelector: View {
    let options: [AtmosphereStyle]
    @Binding var selection: AtmosphereStyle

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = option }
                } label: {
                    Text(option.rawValue.uppercased())
                        .font(Aura.Font.label(11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(selection == option ? Aura.Color.void : Aura.Color.mist)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 16)
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

struct AuraSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AuraLabel(text: title, size: 11, color: Aura.Color.mist.opacity(0.85), tracking: 2)
            GeometryReader { proxy in
                let width = proxy.size.width
                let knobX = CGFloat(value) * width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 2)

                    Capsule()
                        .fill(Aura.Color.auraGradient)
                        .frame(width: max(2, knobX), height: 2)

                    Circle()
                        .fill(Aura.Color.cream)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .offset(x: knobX - 7)
                }
                .contentShape(Rectangle().inset(by: -12))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let newValue = min(max(0, drag.location.x / width), 1)
                            value = newValue
                        }
                )
            }
            .frame(height: 14)
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
