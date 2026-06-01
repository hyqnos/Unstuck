import Foundation
import ActivityKit
import SwiftUI

/// Bridges a focus session to the Dynamic Island / Lock Screen Live Activity.
///
/// Kept deliberately thin: it starts one activity, pushes updated `ContentState`
/// when the mood or music changes, and ends it. The live countdown itself is
/// rendered by the system from `endDate`, so we don't push every second.
///
/// All ActivityKit calls are no-ops on iOS < 16.1 or when the user hasn't
/// enabled Live Activities — they simply do nothing, never crash.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()
    private init() {}

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private var current: Activity<FocusSessionAttributes>? {
        get { _current as? Activity<FocusSessionAttributes> }
        set { _current = newValue }
    }
    private var _current: Any?
    #endif

    /// Mood → (SF Symbol, calm label, accent hex). Mirrors the in-app MoodBadge
    /// so the pill feels like the same object. Never names a clinical state.
    static func visuals(for mode: BrainMode) -> (glyph: String, label: String, hex: String) {
        switch mode {
        case .ready:      return ("bolt.fill",      "in the zone",  "4CD999")
        case .hyperfocus: return ("scope",          "locked in",    "7280FF")
        case .lowBattery: return ("moon.zzz.fill",  "easy does it", "FF9966")
        case .overwhelm:  return ("cloud.fill",     "one thing",    "99A8C7")
        }
    }

    // MARK: - Lifecycle

    func start(title: String, endDate: Date, mode: BrainMode, musicOn: Bool) {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let v = Self.visuals(for: mode)
        let state = FocusSessionAttributes.ContentState(
            endDate: endDate, isPaused: false, pausedRemaining: 0,
            moodGlyph: v.glyph, moodLabel: v.label, accentHex: v.hex, musicOn: musicOn)
        let attributes = FocusSessionAttributes(title: title)

        do {
            current = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: endDate),
                pushType: nil)
        } catch {
            // Most common cause: user has Live Activities off for the app. Stay silent.
        }
    }

    /// Re-push state when mood, music, pause, or end-time changes.
    func update(endDate: Date, isPaused: Bool, pausedRemaining: TimeInterval,
                mode: BrainMode, musicOn: Bool) {
        guard #available(iOS 16.1, *), let activity = current else { return }
        let v = Self.visuals(for: mode)
        let state = FocusSessionAttributes.ContentState(
            endDate: endDate, isPaused: isPaused, pausedRemaining: pausedRemaining,
            moodGlyph: v.glyph, moodLabel: v.label, accentHex: v.hex, musicOn: musicOn)
        Task { await activity.update(.init(state: state, staleDate: endDate)) }
    }

    func end() {
        guard #available(iOS 16.1, *), let activity = current else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.current = nil
        }
    }
}
