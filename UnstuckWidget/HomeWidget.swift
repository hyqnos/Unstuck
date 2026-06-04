import WidgetKit
import SwiftUI

// MARK: - Home-screen widget — a calm, glanceable presence (found, not pushed)

struct CrumbEntry: TimelineEntry {
    let date: Date
    let line: String
}

struct CrumbProvider: TimelineProvider {
    // Baked, universal lines — no labels, no demands, no diagnosis. The widget
    // can't read the app's on-device data without an App Group, so these are
    // gentle constants that rotate. (An App Group could feed live data later.)
    static let lines = [
        "open the fridge, forget why? that's just working memory. it's normal.",
        "a thought you can see is a thought you can put down.",
        "tiny step counts. 2 minutes is a real start.",
        "novelty wakes the brain up — that's why new feels good.",
        "you don't have to finish. you just have to begin.",
        "the dishes exist. that's all — no pressure.",
        "rest is also doing something.",
        "your map is still here. come back whenever.",
    ]

    func placeholder(in context: Context) -> CrumbEntry { CrumbEntry(date: .now, line: Self.lines[1]) }

    func getSnapshot(in context: Context, completion: @escaping (CrumbEntry) -> Void) {
        completion(CrumbEntry(date: .now, line: Self.lines.randomElement() ?? Self.lines[0]))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CrumbEntry>) -> Void) {
        let now = Date()
        let base = Int(now.timeIntervalSince1970 / 3600)
        let entries = (0..<12).map { h -> CrumbEntry in
            let date = Calendar.current.date(byAdding: .hour, value: h, to: now) ?? now
            return CrumbEntry(date: date, line: Self.lines[(base + h) % Self.lines.count])
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct CrumbWidgetView: View {
    var entry: CrumbEntry
    private let teal = Color(red: 0.30, green: 0.85, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Circle().fill(teal).frame(width: 7, height: 7)
                .shadow(color: teal.opacity(0.8), radius: 4)
            Text(entry.line)
                .font(.system(size: 13, weight: .light, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text("unstuck")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.06, green: 0.06, blue: 0.14),
                                    Color(red: 0.01, green: 0.01, blue: 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UnstuckHomeWidget", provider: CrumbProvider()) { entry in
            CrumbWidgetView(entry: entry)
        }
        .configurationDisplayName("A calm crumb")
        .description("A small, found thought from your brain space. No pressure.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Bundle — the home-screen widget + the focus-session Live Activity

@main
struct UnstuckWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeWidget()
        ClusterWidget()   // interactive Home-Screen cluster switcher (from ClusterWidget.swift)
        UnstuckWidget()   // Live Activity / Dynamic Island (from UnstuckWidget.swift)
    }
}
