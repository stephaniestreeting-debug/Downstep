//
//  BreathSummaryView.swift
//  Downstep
//

import SwiftUI
import Charts

struct BreathSummaryView: View {
    let summary: String
    let history: [BreathReading]
    var elapsed: TimeInterval = 0
    /// Seconds from when guidance first kicked in to when breathing settled back
    /// down, if that happened this session.
    var timeToCalmSeconds: Int?
    var timeToCalmIsBest: Bool = false
    /// How many times the de-escalation curve stepped down this session.
    var stepCount: Int = 0
    var startBPM: Double?
    var lowestGuidedBPM: Double?
    var onRestart: () -> Void

    /// "You calmed your breathing in 52 seconds" — a plain fact, never phrased as
    /// praise or evaluation. "— your fastest yet" only appears on a genuine new
    /// personal best (Strava-style: celebrate PRs, stay silent otherwise).
    private var timeToCalmLine: String? {
        guard let seconds = timeToCalmSeconds else { return nil }
        let base = "You calmed your breathing in \(seconds) second\(seconds == 1 ? "" : "s")."
        return timeToCalmIsBest ? base + " Your fastest yet." : base
    }

    /// "You stepped your breathing down 8 times — 24 to 8 breaths a minute." — the
    /// literal "downstep" mechanic, surfaced as a fact rather than folded into copy.
    private var stepLine: String? {
        guard stepCount > 0, let start = startBPM, let lowest = lowestGuidedBPM else { return nil }
        return "You stepped your breathing down \(stepCount) time\(stepCount == 1 ? "" : "s") — \(Int(start.rounded())) to \(Int(lowest.rounded())) breaths a minute."
    }

    /// A plain-text snapshot of this one session — handed to the share sheet, not
    /// stored anywhere by the app. What happens to it after (saved, emailed, etc.)
    /// is entirely up to whoever it's shared with.
    private var shareText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60

        var lines = [
            "Downstep session — \(formatter.string(from: Date()))",
            "Duration: \(minutes)m \(seconds)s",
            summary,
        ]
        if let timeToCalmLine { lines.append(timeToCalmLine) }
        if let stepLine { lines.append(stepLine) }
        if !history.isEmpty {
            lines.append("")
            lines.append("Breathing rate over time:")
            for reading in history {
                let m = Int(reading.time) / 60
                let s = Int(reading.time) % 60
                lines.append(String(format: "  %d:%02d — %.0f breaths/min", m, s, reading.bpm))
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 22) {
            AuraLabel(text: "Session Complete", size: 12, color: Aura.Color.mist.opacity(0.7))

            Text(summary)
                .auraDisplayFont(22)
                .multilineTextAlignment(.center)
                .foregroundStyle(Aura.Color.cream)
                .fixedSize(horizontal: false, vertical: true)

            if timeToCalmLine != nil || stepLine != nil {
                VStack(spacing: 6) {
                    if let timeToCalmLine {
                        Text(timeToCalmLine)
                            .auraFont(13, weight: .medium)
                            .foregroundStyle(Aura.Color.sage)
                    }
                    if let stepLine {
                        Text(stepLine)
                            .auraFont(13, weight: .medium)
                            .foregroundStyle(Aura.Color.mist.opacity(0.8))
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            if history.count > 1 {
                Chart(history) { reading in
                    LineMark(
                        x: .value("Time", reading.time),
                        y: .value("Breaths/min", reading.bpm)
                    )
                    .foregroundStyle(Aura.Color.sage)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", reading.time),
                        y: .value("Breaths/min", reading.bpm)
                    )
                    .foregroundStyle(Aura.Color.sage.opacity(0.12))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .foregroundStyle(Aura.Color.mist.opacity(0.5))
                        AxisGridLine().foregroundStyle(Aura.Color.hairline)
                    }
                }
                .frame(height: 140)
                .padding(.top, 4)
            }

            HStack(spacing: 12) {
                ShareLink(item: shareText) {
                    Text("SHARE")
                        .auraFont(12, weight: .semibold)
                        .tracking(1.5)
                        .foregroundStyle(Aura.Color.cream)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(Aura.Color.hairline, lineWidth: 1))
                }

                Button(action: onRestart) {
                    Text("BEGIN AGAIN")
                        .auraFont(12, weight: .semibold)
                        .tracking(1.5)
                        .foregroundStyle(Aura.Color.void)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(Aura.Color.cream))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Aura.Color.void.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Aura.Color.hairline, lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        BreathSummaryView(
            summary: "Your breathing slowed from ~16 to ~8 breaths a minute.",
            history: (0..<12).map { BreathReading(time: TimeInterval($0 * 20), bpm: Double(16 - $0)) },
            onRestart: {}
        )
        .padding(24)
    }
}
