import AppIntents
import SwiftUI

// MARK: - Intent
// Shows in Settings → Action Button → App Shortcut

struct QuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture a Thought"
    static var description = IntentDescription("Instantly drop a thought into your brain map.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Signal the app to open with capture bar focused
        await MainActor.run {
            NotificationCenter.default.post(name: .actionButtonCapture, object: nil)
        }
        return .result()
    }
}

// MARK: - Shortcuts provider
// Registers the shortcut so it appears in Settings → Action Button

struct UnstuckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickCaptureIntent(),
            phrases: [
                "Capture a thought in \(.applicationName)",
                "Quick capture in \(.applicationName)",
                "Brain dump in \(.applicationName)",
            ],
            shortTitle: "Capture Thought",
            systemImageName: "brain.head.profile"
        )
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let actionButtonCapture = Notification.Name("unstuck.actionButtonCapture")
}
