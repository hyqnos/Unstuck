import Foundation
import Observation

/// Detects how long the user has been away — silently.
/// NEVER says "welcome back" or acknowledges the absence.
/// Just decides whether to show the gentle breadcrumb mode on return.
@Observable
final class ReturnState {
    static let shared = ReturnState()

    /// How long since the last open, captured at launch (before we overwrite it).
    private(set) var gapSinceLastOpen: TimeInterval = 0

    /// True when the user returns after a meaningful absence (a "freeze").
    private(set) var returningFromFreeze = false

    private let lastOpenKey = "unstuck.lastOpenAt"
    private let freezeThreshold: TimeInterval = 60 * 60 * 18  // 18 hours = a real gap

    private init() {}

    /// Call once at launch. Reads the previous open time, then records now.
    func recordOpen() {
        let defaults = UserDefaults.standard
        let now = Date()

        if let last = defaults.object(forKey: lastOpenKey) as? Date {
            gapSinceLastOpen = now.timeIntervalSince(last)
            returningFromFreeze = gapSinceLastOpen >= freezeThreshold
        } else {
            // First ever open — not a freeze
            gapSinceLastOpen = 0
            returningFromFreeze = false
        }

        defaults.set(now, forKey: lastOpenKey)
    }

    /// User chose to enter the map normally — leave breadcrumb mode.
    func dismissFreeze() {
        returningFromFreeze = false
    }

    /// Human phrasing of the gap — used internally, never shown as "you were gone X days".
    var gapDescription: String {
        let days = Int(gapSinceLastOpen / 86400)
        switch days {
        case 0:      return "a little while"
        case 1:      return "a day"
        case 2...6:  return "a few days"
        case 7...29: return "a while"
        default:     return "some time"
        }
    }
}
