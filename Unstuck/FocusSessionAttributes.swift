import ActivityKit
import Foundation

/// Shared contract between the app and the Live Activity / Dynamic Island.
///
/// MUST be a member of BOTH the app target and the widget-extension target
/// (tick both in File Inspector → Target Membership), or the two sides won't
/// agree on the type and the activity won't render.
///
/// `ContentState` is the part that changes during a session; the fixed
/// properties never change once the activity starts.
@available(iOS 16.1, *)
struct FocusSessionAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        /// When the session is scheduled to finish. The system renders the
        /// live countdown from this with `Text(timerInterval:)` — no per-second
        /// updates from the app needed (kind to the battery).
        var endDate: Date

        /// True while paused. When paused we show a static remaining time
        /// instead of a running countdown.
        var isPaused: Bool

        /// Seconds left, frozen, used only while `isPaused == true`.
        var pausedRemaining: TimeInterval

        /// Current brain-mode glyph (SF Symbol) + label — never names a clinical
        /// state; just a calm cue. Updated live as MoodDetector shifts.
        var moodGlyph: String
        var moodLabel: String

        /// Hex (e.g. "FF9E40") used to tint the pill to the current mood.
        var accentHex: String

        /// Whether the mood-reactive focus music bed is currently playing.
        var musicOn: Bool
    }

    /// Fixed for the life of the session.
    var title: String
}
