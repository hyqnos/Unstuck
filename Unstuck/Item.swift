import Foundation
import SwiftData

// MARK: - Enums

enum ZoneType: String, Codable {
    // Organized zones — structured, the "handled" stuff
    case reminders
    case health
    case timeManagement
    case routines

    // Messy zones — patterned chaos, ideas live here
    case ideas
    case captures
    case someday

    var isOrganized: Bool {
        switch self {
        case .reminders, .health, .timeManagement, .routines: return true
        case .ideas, .captures, .someday: return false
        }
    }
}

// Detected from behavior — never asked directly
enum BrainMode: String, Codable {
    case overwhelm   // minimal, ~1 thing
    case lowBattery  // gentle, 2–3 items, warm tones
    case ready       // full view, full voice
    case hyperfocus  // quiet, save insights for after
}

enum ItemState: String, Codable {
    case active
    case fading  // incomplete, cooling — never "overdue"
    case done
}

// MARK: - Models

@Model
final class Cluster {
    var id: UUID
    var zoneType: ZoneType
    var label: String

    // Position on the spatial map (normalized 0–1)
    var positionX: Double
    var positionY: Double

    var createdAt: Date

    // 🔦 User-chosen highlight colour (hex "RRGGBB"); nil = no highlight.
    var highlightHex: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \BrainItem.cluster)
    var items: [BrainItem]

    init(
        zoneType: ZoneType,
        label: String,
        positionX: Double,
        positionY: Double
    ) {
        self.id = UUID()
        self.zoneType = zoneType
        self.label = label
        self.positionX = positionX
        self.positionY = positionY
        self.createdAt = .now
        self.items = []
    }
}

@Model
final class BrainItem {
    var id: UUID

    // The original raw input — the sub-detail you can check
    var text: String
    // AI-named main idea — the clean label shown on the node (nil until named)
    var title: String?

    // 0.0 (cool/peripheral) → 1.0 (urgent/center) — drives map gravity
    var urgency: Double

    var state: ItemState
    var createdAt: Date
    var lastTouchedAt: Date

    // Time estimate in minutes — "5 min" unlocks action
    var estimatedMinutes: Int?

    var cluster: Cluster?

    init(
        text: String,
        title: String? = nil,
        urgency: Double = 0.5,
        cluster: Cluster? = nil,
        estimatedMinutes: Int? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.title = title
        self.urgency = max(0, min(1, urgency))
        self.state = .active
        self.createdAt = .now
        self.lastTouchedAt = .now
        self.estimatedMinutes = estimatedMinutes
        self.cluster = cluster
    }

    /// What the node shows — the named idea, falling back to the raw text.
    var displayLabel: String { title ?? text }

    func touch() {
        lastTouchedAt = .now
    }
}
