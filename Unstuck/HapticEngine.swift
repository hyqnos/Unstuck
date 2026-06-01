import UIKit

/// Centralised haptic variety engine.
/// Tracks the last pattern fired and rotates so the same one never repeats twice in a row.
final class HapticEngine {
    static let shared = HapticEngine()
    private init() {}

    enum Reward: CaseIterable {
        case soft, light, medium, rigid, success, warning, selectionTap
    }

    private var last: Reward?

    // Call this for any positive action — capture, complete, unlock, etc.
    func reward(_ preferred: Reward = .medium) {
        let pick = preferred == last ? rotate(from: preferred) : preferred
        last = pick
        fire(pick)
    }

    // Specific one-shots (don't affect variety rotation)
    func complete()  { fire(.success) }
    func tap()       { fire(.selectionTap) }
    func land()      { fire(.medium) }
    func settle()    { fire(.soft) }

    /// Gyro-aware fling haptic.
    /// rotationRate (rad/s) from CMGyroData — the wrist snap intensity at release.
    ///   < 1.0  → soft flick
    ///   1–3    → medium throw
    ///   3–6    → rigid snap
    ///   > 6    → success burst (full wrist snap)
    func fling(rotationRate: Double) {
        switch rotationRate {
        case ..<1.0:
            fire(.soft)
        case 1.0..<3.0:
            fire(.medium)
        case 3.0..<6.0:
            fire(.rigid)
        default:
            // Full wrist snap — double hit for maximum satisfaction
            fire(.rigid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: - Private

    private func rotate(from avoided: Reward) -> Reward {
        let others = Reward.allCases.filter { $0 != avoided }
        return others.randomElement() ?? .light
    }

    private func fire(_ reward: Reward) {
        switch reward {
        case .soft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .rigid:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selectionTap:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

}
