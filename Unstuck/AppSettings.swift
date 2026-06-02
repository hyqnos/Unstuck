import Foundation
import Observation

/// Sensory intensity dial.
///  • calm   — flattens gyro 3D, mutes spatial audio, no chaos, no laser shows
///  • normal — the balanced default
///  • insane — the rave never stops: laser show on every completion, max intensity,
///             bigger tilt, frequent chaos drops
enum SensoryLevel: String { case calm, normal, insane }

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var sensory: SensoryLevel {
        didSet { UserDefaults.standard.set(sensory.rawValue, forKey: Self.key) }
    }

    /// Mood-reactive focus music bed.
    var focusMusic: Bool {
        didSet { UserDefaults.standard.set(focusMusic, forKey: Self.musicKey) }
    }

    /// Has the user seen the first-run intro?
    var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: Self.onboardKey) }
    }

    /// Ambient companion presence (corner creature). On by default; fully dismissible.
    var companionOn: Bool {
        didSet { UserDefaults.standard.set(companionOn, forKey: Self.companionKey) }
    }

    // Convenience gates used throughout the app
    var calmMode: Bool   { sensory == .calm }
    var insaneMode: Bool { sensory == .insane }

    private static let key = "unstuck.sensoryLevel"
    private static let musicKey = "unstuck.focusMusic"
    private static let onboardKey = "unstuck.hasOnboarded"
    private static let companionKey = "unstuck.companionOn"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        sensory = SensoryLevel(rawValue: raw ?? "") ?? .normal
        focusMusic = UserDefaults.standard.bool(forKey: Self.musicKey)
        hasOnboarded = UserDefaults.standard.bool(forKey: Self.onboardKey)
        // Default ON for new installs (key absent) so the presence is discovered.
        companionOn = UserDefaults.standard.object(forKey: Self.companionKey) as? Bool ?? true
    }

    /// Cycle calm → normal → insane → calm
    func cycle() {
        switch sensory {
        case .calm:   sensory = .normal
        case .normal: sensory = .insane
        case .insane: sensory = .calm
        }
    }
}

extension Notification.Name {
    static let taskCompleted = Notification.Name("unstuck.taskCompleted")
}
