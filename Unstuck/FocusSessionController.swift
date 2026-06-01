import Foundation
import SwiftUI

/// Owns a single focus session: its title, how long it runs, pause/resume, and
/// end. Drives the in-app countdown AND keeps the Dynamic Island Live Activity
/// in sync (via `LiveActivityService`).
///
/// PDA-safe by design: a session is always something the user *pulls* (starts
/// it themselves) and can dismiss at any moment. Nothing here nags, and ending
/// early is never framed as failure — `end()` is just "done," same as finishing.
@Observable
@MainActor
final class FocusSessionController {
    static let shared = FocusSessionController()
    private init() {}

    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var title = "Focus"
    private(set) var endDate = Date()

    /// Frozen seconds-left while paused (so the in-app ring holds still).
    private(set) var pausedRemaining: TimeInterval = 0

    /// Seconds left right now (for in-app UI; the pill counts down on its own).
    var remaining: TimeInterval {
        isPaused ? pausedRemaining : max(0, endDate.timeIntervalSinceNow)
    }

    private var ticker: Timer?

    // MARK: - Lifecycle

    func start(title: String, minutes: Double) {
        self.title = title
        self.endDate = Date().addingTimeInterval(minutes * 60)
        self.isPaused = false
        self.isActive = true

        LiveActivityService.shared.start(
            title: title, endDate: endDate,
            mode: MoodDetector.shared.mode, musicOn: AppSettings.shared.focusMusic)
        startTicker()
    }

    func pause() {
        guard isActive, !isPaused else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        isPaused = true
        pushUpdate()
    }

    func resume() {
        guard isActive, isPaused else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        isPaused = false
        pushUpdate()
    }

    /// Done — whether the timer ran out or the user tapped away. No failure framing.
    func end() {
        isActive = false
        isPaused = false
        ticker?.invalidate(); ticker = nil
        LiveActivityService.shared.end()
    }

    /// Call when the mood or the focus-music toggle changes mid-session, so the
    /// pill recolors / updates its music note live.
    func refreshVisuals() {
        guard isActive else { return }
        pushUpdate()
    }

    // MARK: - Internals

    private func pushUpdate() {
        LiveActivityService.shared.update(
            endDate: endDate, isPaused: isPaused, pausedRemaining: pausedRemaining,
            mode: MoodDetector.shared.mode, musicOn: AppSettings.shared.focusMusic)
    }

    private func startTicker() {
        ticker?.invalidate()
        // 1 Hz, only to auto-end at zero and let in-app views observe `remaining`.
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive, !self.isPaused else { return }
                if self.remaining <= 0 { self.end() }
            }
        }
    }
}
