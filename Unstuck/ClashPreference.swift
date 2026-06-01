import Foundation

/// Learns which kinds of events the user tends to protect when two overlap.
/// Each time they keep one over another, the kept event's words gain weight and
/// the dropped event's words lose a little. Local, private, improves over time.
final class ClashPreference {
    static let shared = ClashPreference()

    private var weights: [String: Double]
    private let key = "unstuck.clashPreference"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            weights = decoded
        } else {
            weights = [:]
        }
    }

    /// Preference score for a title — average weight of its meaningful words. [-1…1]
    func score(_ title: String) -> Double {
        let toks = Self.tokens(title)
        let vals = toks.compactMap { weights[$0] }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// The user kept `kept` over `dropped` — reinforce that pattern.
    func reinforce(kept: String, over dropped: String) {
        for t in Self.tokens(kept)    { weights[t, default: 0] = min(1.0, weights[t, default: 0] + 0.2) }
        for t in Self.tokens(dropped) { weights[t, default: 0] = max(-1.0, weights[t, default: 0] - 0.1) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(weights) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // Meaningful words only — lowercase, length > 3, no filler
    private static let filler: Set<String> = ["with", "the", "and", "for", "from", "your", "this", "that", "call", "meet"]
    static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !filler.contains($0) }
    }
}
