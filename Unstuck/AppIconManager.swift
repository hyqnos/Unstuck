import UIKit

/// Swaps the home-screen app icon to match the detected brain mode.
/// iOS shows a confirmation alert whenever an app changes its icon (no public way
/// to suppress it), so we only change on backgrounding — the icon reflects the mood
/// you left in and greets you next launch, without interrupting mid-session.
enum AppIconManager {
    static func iconName(for mode: BrainMode) -> String? {
        switch mode {
        case .ready:      return "IconReady"
        case .hyperfocus: return "IconFocus"
        case .lowBattery: return "IconLow"
        case .overwhelm:  return "IconOverwhelm"
        }
    }

    @MainActor
    static func update(for mode: BrainMode) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target = iconName(for: mode)
        // Skip if it's already the right icon — avoids a redundant alert
        guard UIApplication.shared.alternateIconName != target else { return }
        UIApplication.shared.setAlternateIconName(target)
    }
}
