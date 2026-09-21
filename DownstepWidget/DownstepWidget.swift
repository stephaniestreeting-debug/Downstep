//
//  DownstepWidget.swift
//  DownstepWidgetExtension
//
//  A static, single-purpose widget: the whole surface is a "Begin" shortcut
//  that deep-links into the app via the "downstep://begin" URL, which
//  DownstepApp.swift catches to start a session immediately — every tap
//  counts when someone reaches for this mid-panic. Real-time audio/mic
//  capture can't run inside a widget extension process, so opening the
//  containing app is unavoidable; this just skips the extra tap to get there.
//

import WidgetKit
import SwiftUI

private enum WidgetAura {
    static let void = Color(red: 0.05, green: 0.07, blue: 0.07)
    static let cream = Color(red: 0.93, green: 0.91, blue: 0.85)
    static let mist = Color(red: 0.78, green: 0.82, blue: 0.80)
}

struct BeginEntry: TimelineEntry {
    let date: Date
}

struct BeginProvider: TimelineProvider {
    func placeholder(in context: Context) -> BeginEntry {
        BeginEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (BeginEntry) -> Void) {
        completion(BeginEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeginEntry>) -> Void) {
        completion(Timeline(entries: [BeginEntry(date: Date())], policy: .never))
    }
}

struct DownstepWidgetView: View {
    var body: some View {
        Link(destination: URL(string: "downstep://begin")!) {
            ZStack {
                WidgetAura.void

                VStack(spacing: 12) {
                    Text("DOWNSTEP")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(WidgetAura.mist.opacity(0.75))

                    Text("Begin")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WidgetAura.void)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(WidgetAura.cream))
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct DownstepWidget: Widget {
    let kind: String = "DownstepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BeginProvider()) { _ in
            DownstepWidgetView()
        }
        .configurationDisplayName("Downstep")
        .description("One tap to start a calming session.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct DownstepWidgetBundle: WidgetBundle {
    var body: some Widget {
        DownstepWidget()
    }
}
