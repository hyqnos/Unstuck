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

    /// Set when a milestone is crossed — the map watches this and reveals it.
    var pendingMilestone: Milestone?

    // Completion milestones — the main "collection" ladder
    private let marks = [1, 3, 7, 15, 30, 60, 120, 250, 500]

    private let capturedKey  = "unstuck.captured"
    private let completedKey  = "unstuck.completed"
    private let creditsKey   = "unstuck.credits"

    private init() {
        captured  = UserDefaults.standard.integer(forKey: capturedKey)
        completed = UserDefaults.standard.integer(forKey: completedKey)
        credits   = UserDefaults.standard.integer(forKey: creditsKey)
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
    @discardableResult
    func awardCredits(estimatedMinutes: Int?) -> (amount: Int, jackpot: Bool) {
        let m = estimatedMinutes ?? 5
        let amount: Int
        let jackpot: Bool
        switch m {
        case ..<5:    amount = 10;  jackpot = false
        case 5..<15:  amount = 20;  jackpot = false
        case 15..<30: amount = 50;  jackpot = false
        default:      amount = 200; jackpot = true     // the 777 / $$$ row
        }
        credits += amount
        UserDefaults.standard.set(credits, forKey: creditsKey)
        return (amount, jackpot)
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
