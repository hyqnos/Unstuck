import Foundation
import SwiftData
import Observation

@Observable
final class PatternService {
    private(set) var crumbs: [KnowledgeCrumb] = []

    static let shared = PatternService()
    private init() {}

    // MARK: - Analyse

    @MainActor
    func analyse(clusters: [Cluster]) {
        var result: [KnowledgeCrumb] = KnowledgeCrumb.makeFacts(count: 5)
        let patternCrumbs = derivePatterns(from: clusters)
        result.append(contentsOf: patternCrumbs)
        crumbs = result
    }

    // MARK: - Pattern derivation

    private func derivePatterns(from clusters: [Cluster]) -> [KnowledgeCrumb] {
        let allItems = clusters.flatMap { $0.items }
        guard allItems.count >= 3 else { return [] }

        var patterns: [KnowledgeCrumb] = []

        // Peak capture hour
        if let peakHour = peakCaptureHour(items: allItems) {
            let label = hourLabel(peakHour)
            patterns.append(.makePattern(
                text: "most of your thoughts arrive around \(label). your brain's capture window.",
                positionX: 0.72, positionY: 0.42
            ))
        }

        // Favourite zone
        if let fav = favouriteZone(clusters: clusters) {
            patterns.append(.makePattern(
                text: "your mind gravitates toward \(fav). that's where the energy lives right now.",
                positionX: 0.28, positionY: 0.62
            ))
        }

        // Completion pattern
        let doneCount = allItems.filter { $0.state == .done }.count
        let total = allItems.count
        if total >= 5 {
            let rate = Int(Double(doneCount) / Double(total) * 100)
            let message: String
            switch rate {
            case 0..<20:
                message = "\(rate)% of nodes are done. things are accumulating — not a problem, just a pile."
            case 20..<60:
                message = "\(rate)% of nodes are done. steady movement. the brain is working."
            default:
                message = "\(rate)% done. something's clicking. that's real momentum."
            }
            patterns.append(.makePattern(text: message, positionX: 0.55, positionY: 0.75))
        }

        // Capture streak
        if let streakMsg = captureStreak(items: allItems) {
            patterns.append(.makePattern(text: streakMsg, positionX: 0.42, positionY: 0.30))
        }

        return patterns
    }

    // MARK: - Helpers

    private func peakCaptureHour(items: [BrainItem]) -> Int? {
        guard items.count >= 5 else { return nil }
        var counts = [Int: Int]()
        for item in items {
            let hour = Calendar.current.component(.hour, from: item.createdAt)
            counts[hour, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func favouriteZone(clusters: [Cluster]) -> String? {
        clusters
            .filter { !$0.items.isEmpty }
            .max(by: { $0.items.count < $1.items.count })
            .map { $0.label }
    }

    private func captureStreak(items: [BrainItem]) -> String? {
        let calendar = Calendar.current
        let days = Set(items.map { calendar.startOfDay(for: $0.createdAt) })
        guard days.count >= 2 else { return nil }

        var streak = 1
        var current = calendar.startOfDay(for: Date())
        while days.contains(calendar.date(byAdding: .day, value: -1, to: current)!) {
            streak += 1
            current = calendar.date(byAdding: .day, value: -1, to: current)!
        }

        guard streak >= 2 else { return nil }
        return "\(streak) days of captures in a row. consistency is just showing up. you're showing up."
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0...5:   return "the middle of the night"
        case 6...8:   return "early morning"
        case 9...11:  return "mid-morning"
        case 12...13: return "around noon"
        case 14...16: return "the afternoon"
        case 17...19: return "early evening"
        case 20...21: return "evening"
        default:      return "late night"
        }
    }
}
