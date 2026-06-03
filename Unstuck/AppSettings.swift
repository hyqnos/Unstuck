import Foundation
import Observation

/// Sensory intensity dial.
///  • calm   — flattens gyro 3D, mutes spatial audio, no chaos, no laser shows
///  • normal — the balanced default
///  • insane — the rave never stops: laser show on every completion, max intensity,
///             bigger tilt, frequent chaos drops
enum SensoryLevel: String { case calm, normal, insane }

/// Which companion character is shown. Native variants ship today; `.live2d` is the
/// drop-in slot for a future Live2D Cubism model (see docs/LIVE2D.md). Swappable
/// characters fight novelty death; collectible models are a future monetisation idea.
enum CompanionCharacter: String, CaseIterable, Codable {
    case lion, fox, bear     // native 3D (SceneKit) creatures — built in code, no assets
    case orb                 // native 2D breathing orb (also the Reduce-Motion fallback)
    case live2d              // a Live2D model, once you add one

    var label: String {
        switch self {
        case .lion: return "lion";  case .fox: return "fox";  case .bear: return "bear"
        case .orb:  return "orb";   case .live2d: return "live2d"
        }
    }
    var isNative3D: Bool { self == .lion || self == .fox || self == .bear }
}

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

    /// Adaptive mood reading. Off = a no-demand neutral look that never tries to
    /// read you — CLAUDE.md's "no-demand mode where the app only reflects."
    var adaptiveMood: Bool {
        didSet { UserDefaults.standard.set(adaptiveMood, forKey: Self.adaptiveKey) }
    }

    /// Which companion character is shown (native variants + a Live2D slot).
    var companionCharacter: CompanionCharacter {
        didSet { UserDefaults.standard.set(companionCharacter.rawValue, forKey: Self.charKey) }
    }

    // Convenience gates used throughout the app
    var calmMode: Bool   { sensory == .calm }
    var insaneMode: Bool { sensory == .insane }

    private static let key = "unstuck.sensoryLevel"
    private static let musicKey = "unstuck.focusMusic"
    private static let onboardKey = "unstuck.hasOnboarded"
    private static let companionKey = "unstuck.companionOn"
    private static let adaptiveKey = "unstuck.adaptiveMood"
    private static let charKey = "unstuck.companionCharacter"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        sensory = SensoryLevel(rawValue: raw ?? "") ?? .normal
        focusMusic = UserDefaults.standard.bool(forKey: Self.musicKey)
        hasOnboarded = UserDefaults.standard.bool(forKey: Self.onboardKey)
        // Default ON for new installs (key absent) so the presence is discovered.
        companionOn = UserDefaults.standard.object(forKey: Self.companionKey) as? Bool ?? true
        adaptiveMood = UserDefaults.standard.object(forKey: Self.adaptiveKey) as? Bool ?? true
        companionCharacter = CompanionCharacter(rawValue: UserDefaults.standard.string(forKey: Self.charKey) ?? "") ?? .lion
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
