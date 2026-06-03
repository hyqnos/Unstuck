import UIKit
import CoreHaptics

/// Centralised haptic variety engine.
/// Tracks the last pattern fired and rotates so the same one never repeats twice in a row.
/// Core Haptics powers the hold-to-claim charge ramp + payoff burst (the Brawl-Stars
/// "charge then explode" feel); everything degrades to UIKit haptics where Core
/// Haptics isn't available (Simulator / older devices).
final class HapticEngine {
    static let shared = HapticEngine()
    private init() {}

    private var engine: CHHapticEngine?

    private func ensureEngine() {
        guard engine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true                 // sleeps when idle (battery)
            e.resetHandler = { [weak e] in try? e?.start() }
            try e.start()
            engine = e
        } catch { engine = nil }
    }

    /// One "charge" tick during a hold — strength scales with 0…1 progress, so the
    /// thumb feels the tension build. Honest: only fired while a real hold is in progress.
    func chargeTick(_ p: Double) {
        let p = max(0, min(1, p))
        ensureEngine()
        if let engine {
            let ev = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(0.25 + 0.75 * p)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(0.20 + 0.80 * p)),
            ], relativeTime: 0)
            if let pattern = try? CHHapticPattern(events: [ev], parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                try? player.start(atTime: 0)
                return
            }
        }
        // Fallback: stepped UIKit impact
        let style: UIImpactFeedbackGenerator.FeedbackStyle =
            p < 0.4 ? .soft : (p < 0.7 ? .light : (p < 0.95 ? .medium : .rigid))
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: CGFloat(0.4 + 0.6 * p))
    }

    /// The payoff at claim — a rapid escalating burst, ending in a satisfying boom.
    /// `big` for the heavier tiers (a real win / wall came down).
    func claimBurst(big: Bool = false) {
        ensureEngine()
        if let engine {
            var events: [CHHapticEvent] = []
            let n = big ? 6 : 4
            for i in 0..<n {
                let f = Double(i) / Double(max(1, n - 1))
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(0.5 + 0.5 * f)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(0.3 + 0.7 * f)),
                ], relativeTime: Double(i) * 0.05))
            }
            if big {   // a final low rumble — the "boom"
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
                ], relativeTime: Double(n) * 0.05, duration: 0.28))
            }
            if let pattern = try? CHHapticPattern(events: events, parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                try? player.start(atTime: 0)
                return
            }
        }
        // Fallback: rigid hit → success
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

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
