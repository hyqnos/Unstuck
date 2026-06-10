import Foundation
import Observation

/// Collection & reward psychology applied to REAL progress.
/// Tracks genuine wins (thoughts externalized, things cleared) and fires a
/// focus-taking reveal at milestones. Rewards are always real — never fake.
///
/// Three-risk safe: the meter only grows or rests. No streaks, no decay,
/// no "you missed" — resting is never punished.
@MainActor
@Observable
final class Progression {
    static let shared = Progression()

    private(set) var captured: Int
    private(set) var completed: Int
    private(set) var credits: Int          // Top Dollar credits — EARNED, never rolled
    private(set) var completionTimes: [Double] = []   // timestamps, for personal records (you vs your past self)

    /// Set when a milestone is crossed — the map watches this and reveals it.
    var pendingMilestone: Milestone?

    // Completion milestones — the main "collection" ladder
    private let marks = [1, 3, 7, 15, 30, 60, 120, 250, 500]
    var milestones: [Int] { marks }   // exposed for the "look what you did" view

    // MARK: - Personal records (you vs. your past self — never vs. anyone else; RSD-safe)
    private var completionDates: [Date] { completionTimes.map { Date(timeIntervalSince1970: $0) } }
    var bestDay: Int {
        let cal = Calendar.current
        return Dictionary(grouping: completionDates) { cal.startOfDay(for: $0) }.values.map(\.count).max() ?? 0
    }
    var bestWeek: Int {
        let cal = Calendar.current
        return Dictionary(grouping: completionDates) {
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0)) ?? $0
        }.values.map(\.count).max() ?? 0
    }
    var activeDays: Int {
        let cal = Calendar.current
        return Set(completionDates.map { cal.startOfDay(for: $0) }).count
    }
    var thisWeekCount: Int {
        let cal = Calendar.current
        let w = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return completionDates.filter { cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0) == w }.count
    }

    private let capturedKey  = "unstuck.captured"
    private let completedKey  = "unstuck.completed"
    private let creditsKey   = "unstuck.credits"
    private let timesKey     = "unstuck.completionTimes"

    private init() {
        captured  = UserDefaults.standard.integer(forKey: capturedKey)
        completed = UserDefaults.standard.integer(forKey: completedKey)
        credits   = UserDefaults.standard.integer(forKey: creditsKey)
        completionTimes = UserDefaults.standard.array(forKey: timesKey) as? [Double] ?? []
    }

    // MARK: - Record real wins

    func recordCapture() {
        captured += 1
        UserDefaults.standard.set(captured, forKey: capturedKey)
    }

    func recordCompletion() {
        let before = completed
        completed += 1
        UserDefaults.standard.set(completed, forKey: completedKey)

        completionTimes.append(Date().timeIntervalSince1970)
        if completionTimes.count > 400 { completionTimes.removeFirst(completionTimes.count - 400) }  // bounded
        UserDefaults.standard.set(completionTimes, forKey: timesKey)

        if marks.contains(completed), completed > before {
            pendingMilestone = Milestone(count: completed,
                                         tier: tier(for: completed),
                                         caption: caption(for: completed))
        }
    }

    /// Top Dollar payout — **earned, never rolled.** The amount is a deterministic function of the
    /// real effort (the time estimate), so the same task always pays the same: the reels are
    /// theatre, the number is honest. Wall tasks (≥30 min) hit the 777/$$$ jackpot row. No RNG,
    /// no variable-ratio — the slot *feeling* with zero gambling underneath.
    /// Earned multipliers — tied to REAL significance, never a dice roll: clearing a whole
    /// cluster, or finally doing a task you'd been avoiding, is genuinely worth more. So a
    /// jackpot can hit on a *small* task too — when finishing it is a real moment.
    /// A "wall" task — the dreaded ≥30-min kind. THE single source of truth for the
    /// threshold (the claim burst and the jackpot tier both key off this).
    static let wallMinutes = 30

    @discardableResult
    func awardCredits(estimatedMinutes: Int?, clearedCluster: Bool = false, wasAvoided: Bool = false)
        -> (amount: Int, jackpot: Bool, multiplier: Int) {
        let m = estimatedMinutes ?? 5
        var base: Int
        var jackpot: Bool
        if m >= Self.wallMinutes { base = 200; jackpot = true }   // the 777 / $$$ row
        else if m >= 15          { base = 50;  jackpot = false }
        else if m >= 5           { base = 20;  jackpot = false }
        else                     { base = 10;  jackpot = false }
        var multiplier = 1
        if wasAvoided     { multiplier *= 2 }                  // you cleared something you'd been dodging
        if clearedCluster { multiplier *= 2; jackpot = true }  // you emptied the whole cluster → a jackpot moment
        let amount = base * multiplier
        credits += amount
        UserDefaults.standard.set(credits, forKey: creditsKey)
        return (amount, jackpot, multiplier)
    }

    // MARK: - The "almost-there" pull (progress to next mark)

    var nextMark: Int { marks.first(where: { $0 > completed }) ?? completed }
    var prevMark: Int { marks.last(where: { $0 <= completed }) ?? 0 }

    /// 0…1 toward the next milestone — the bar that's almost full.
    var progressToNext: Double {
        let span = nextMark - prevMark
        guard span > 0 else { return 1 }
        return Double(completed - prevMark) / Double(span)
    }

    // MARK: - Tier + caption (insight-framed, rotating — fights habituation)

    private func tier(for n: Int) -> DropTier {
        switch n {
        case ..<3:   return .common
        case ..<7:   return .rare
        case ..<15:  return .epic
        case ..<30:  return .mythic
        case ..<120: return .legendary
        default:     return .chaos
        }
    }

    private func caption(for n: Int) -> String {
        let lines = [
            "\(n) cleared. the momentum is real.",
            "\(n). your constellation is growing.",
            "\(n) things, externalized. that's the whole game.",
            "\(n). the brain trusts a map it can see fill.",
            "\(n) done — each one was a real start.",
        ]
        return lines[n % lines.count]
    }
}

struct Milestone: Equatable {
    let count: Int
    let tier: DropTier
    let caption: String
}
