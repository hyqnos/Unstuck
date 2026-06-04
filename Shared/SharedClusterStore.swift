import Foundation

/// A tiny, glanceable snapshot of the user's clusters, shared between the app and the
/// home-screen widget through the App Group. The widget can't read SwiftData directly,
/// so the app writes this summary and the widget reads it. No personal content — only
/// the cluster names + active counts the user already sees on their own map.
public struct ClusterSummary: Codable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let count: Int          // active (not-done) items
    public let tintHex: String
    public init(id: String, label: String, count: Int, tintHex: String) {
        self.id = id; self.label = label; self.count = count; self.tintHex = tintHex
    }
}

/// `nonisolated` throughout: the widget's TimelineProvider and the cycle intent call
/// this from non-main contexts. It's just App-Group `UserDefaults` access.
public enum SharedClusterStore {
    // nonisolated computed constants — under MainActor-default isolation, plain
    // `static let`s would be actor-isolated and unreachable from the widget's
    // nonisolated TimelineProvider / AppIntent. Computed nonisolated keeps them free.
    nonisolated public static var appGroup: String { "group.Dopa.Unstuck" }
    nonisolated private static var kSummaries: String { "cluster.summaries" }
    nonisolated private static var kIndex: String { "cluster.index" }

    nonisolated private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    nonisolated public static func write(_ summaries: [ClusterSummary]) {
        guard let d = defaults else { return }
        if let data = try? JSONEncoder().encode(summaries) { d.set(data, forKey: kSummaries) }
        let n = summaries.count
        if n > 0 { d.set(((d.integer(forKey: kIndex) % n) + n) % n, forKey: kIndex) }   // keep in range
    }

    nonisolated public static func read() -> [ClusterSummary] {
        guard let d = defaults, let data = d.data(forKey: kSummaries),
              let s = try? JSONDecoder().decode([ClusterSummary].self, from: data) else { return [] }
        return s
    }

    nonisolated public static var index: Int {
        get { defaults?.integer(forKey: kIndex) ?? 0 }
        set { defaults?.set(newValue, forKey: kIndex) }
    }

    /// Advance the selected cluster by ±1, wrapping. Returns the new index.
    @discardableResult
    nonisolated public static func advance(by step: Int) -> Int {
        let n = read().count
        guard n > 0 else { return 0 }
        let next = (((index + step) % n) + n) % n
        index = next
        return next
    }

    nonisolated public static var current: ClusterSummary? {
        let s = read(); guard !s.isEmpty else { return nil }
        return s[((index % s.count) + s.count) % s.count]
    }
}
