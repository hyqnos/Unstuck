import Foundation
import SwiftData

/// The user's own insight, captured on a good day, replayed during a freeze.
/// Their own voice — no outside authority, no coaching from the app.
@Model
final class CoachingNote {
    var id: UUID
    var text: String
    var createdAt: Date
    var timesShown: Int

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.createdAt = .now
        self.timesShown = 0
    }
}
