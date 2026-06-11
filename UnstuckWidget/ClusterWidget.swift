import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Interactive intent — cycle the selected cluster from the Home Screen
// Tapping ‹ › runs this in the widget process: it advances the shared index and asks
// WidgetKit to reload. No demand, no nag — it just steps. (PDA-safe, like the in-app pager.)
struct CycleClusterIntent: AppIntent {
    static var title: LocalizedStringResource = "Cycle clusters"
    static var isDiscoverable: Bool = false          // widget-only; not in Shortcuts/Spotlight

    @Parameter(title: "Direction") var direction: Int

    init() {}
    init(_ direction: Int) { self.direction = direction }

    func perform() async throws -> some IntentResult {
        SharedClusterStore.advance(by: direction)
        WidgetCenter.shared.reloadTimelines(ofKind: "UnstuckClusterWidget")
        return .result()
    }
}

// MARK: - Timeline
struct ClusterEntry: TimelineEntry {
    let date: Date
    let summaries: [ClusterSummary]
    let index: Int
}

struct ClusterProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClusterEntry {
        ClusterEntry(date: .now,
                     summaries: [ClusterSummary(id: "p", label: "reminders", count: 3, tintHex: "4CD9BF")],
                     index: 0)
    }
    func getSnapshot(in context: Context, completion: @escaping (ClusterEntry) -> Void) { completion(now()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClusterEntry>) -> Void) {
        // The intent reloads on every tap; this is just the idle refresh cadence.
        completion(Timeline(entries: [now()], policy: .after(Date().addingTimeInterval(1800))))
    }
    private func now() -> ClusterEntry {
        ClusterEntry(date: .now, summaries: SharedClusterStore.read(), index: SharedClusterStore.index)
    }
}

// MARK: - View
struct ClusterWidgetView: View {
    var entry: ClusterEntry

    private var idx: Int {
        let n = entry.summaries.count; guard n > 0 else { return 0 }
        return ((entry.index % n) + n) % n
    }
    private var current: ClusterSummary? { entry.summaries.isEmpty ? nil : entry.summaries[idx] }
    private var col: Color { Color(hex: current?.tintHex ?? "4CD9BF") }

    var body: some View {
        Group {
            if let c = current { content(c) } else { emptyState }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.06, green: 0.06, blue: 0.14),
                                    Color(red: 0.01, green: 0.01, blue: 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func content(_ c: ClusterSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("cluster").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
                Spacer()
                Text("\(idx + 1)/\(entry.summaries.count)").font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer(minLength: 0)
            Text(c.label)
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95)).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Text("\(c.count)").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(col)
                ForEach(0..<min(c.count, 6), id: \.self) { _ in Circle().fill(col.opacity(0.85)).frame(width: 4, height: 4) }
                if c.count == 0 {
                    Text("clear").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.25))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(intent: CycleClusterIntent(-1)) { chevron("chevron.left") }.buttonStyle(.plain)
                dots
                Button(intent: CycleClusterIntent(1)) { chevron("chevron.right") }.buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var dots: some View {
        let n = entry.summaries.count
        if n <= 8 {
            HStack(spacing: 4) {
                ForEach(0..<n, id: \.self) { k in
                    Capsule().fill(k == idx ? col : Color.white.opacity(0.2))
                        .frame(width: k == idx ? 12 : 4, height: 4)
                }
            }.frame(maxWidth: .infinity)
        } else {
            Spacer()
        }
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.white.opacity(0.08)))
            .overlay(Circle().stroke(col.opacity(0.4), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Circle().fill(Color(hex: "4CD9BF")).frame(width: 7, height: 7)
            Text("your map lives here")
                .font(.system(size: 13, weight: .light, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            Text("clusters appear here as you add them")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ClusterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UnstuckClusterWidget", provider: ClusterProvider()) { entry in
            ClusterWidgetView(entry: entry)
        }
        .configurationDisplayName("Cluster switcher")
        .description("Flip through your map's clusters right from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// hex→Color comes from the target-internal Color(hex:) in UnstuckWidget.swift.
