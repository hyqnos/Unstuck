import Foundation
// Apple Intelligence's on-device model lives in FoundationModels, which only exists
// on very recent OSes. Gating it (compile-time canImport + runtime #available) lets
// the app run on the far wider base of older devices — which matters for the shared
// or hand-me-down iPads/iPhones common in schools — falling back to keyword routing.
#if canImport(FoundationModels)
import FoundationModels
#endif

actor ClusterClassifier {
    static let shared = ClusterClassifier()

    private var session: Any?          // LanguageModelSession on iOS 26+, else nil → keyword fallback
    private var sessionTried = false

    init() {}

    /// Lazily create the model session on first classify — never during view init.
    private func ensureSession() {
        guard !sessionTried else { return }
        sessionTried = true
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }
        guard SystemLanguageModel.default.isAvailable else { return }
        session = LanguageModelSession(instructions: """
        You classify short thoughts, tasks, or ideas into exactly one zone.

        Zones:
        - reminders: things to remember, errands, to-dos, calls to make
        - health: meds, sleep, exercise, food, body, mental health
        - timeManagement: deadlines, schedules, appointments, time blocks
        - routines: recurring habits, daily patterns, rituals
        - ideas: creative thoughts, inspiration, brainstorms, projects
        - someday: future dreams, wishlist, maybe-later, aspirations
        - captures: anything vague, unclear, or that doesn't fit elsewhere

        Reply with ONLY the zone name. No punctuation, no explanation.
        """)
        #endif
    }

    func classify(text: String) async -> ZoneType {
        await classifyAndName(text: text).zone
    }

    /// Classifies the zone AND names the task by its main idea.
    /// The clean title becomes the node label; the raw input stays as a sub-detail.
    func classifyAndName(text: String) async -> (zone: ZoneType, title: String) {
        ensureSession()
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let session = session as? LanguageModelSession {
            return await classifyWithModel(text: text, session: session)
        }
        #endif
        return (classifyWithKeywords(text: text), heuristicTitle(text))
    }

    // MARK: - On-device model (real device with Apple Intelligence)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func classifyWithModel(text: String, session: LanguageModelSession) async -> (zone: ZoneType, title: String) {
        let prompt = """
        Thought: "\(text)"

        1. Pick the single best zone.
        2. Write a 2–5 word task name capturing the MAIN IDEA (imperative, no quotes).

        Reply EXACTLY as: zone | task name
        """
        do {
            let response = try await session.respond(to: prompt)
            let parts = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "|", maxSplits: 1)
            let zoneRaw = parts.first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            let zone = ZoneType(rawValue: zoneRaw) ?? classifyWithKeywords(text: text)
            let title = parts.count > 1
                ? cleanTitle(String(parts[1]))
                : heuristicTitle(text)
            return (zone, title.isEmpty ? heuristicTitle(text) : title)
        } catch {
            return (classifyWithKeywords(text: text), heuristicTitle(text))
        }
    }
    #endif

    // MARK: - Title helpers

    private func cleanTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'.“”"))
        guard let first = t.first else { return t }
        return first.uppercased() + t.dropFirst()
    }

    private func heuristicTitle(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        // Short enough — just sentence-case it
        if t.count <= 42 {
            return t.prefix(1).uppercased() + t.dropFirst()
        }
        // Otherwise take the first handful of words
        let words = t.split(separator: " ").prefix(6).joined(separator: " ")
        return (words.prefix(1).uppercased() + words.dropFirst()) + "…"
    }

    // MARK: - Keyword fallback (Simulator / no Apple Intelligence)

    nonisolated func classifyWithKeywords(text: String) -> ZoneType {   // nonisolated (pure) + unit-tested
        let t = text.lowercased()

        let rules: [(ZoneType, [String])] = [
            (.health,         ["med", "pill", "vitamin", "sleep", "exercise", "gym", "run", "eat", "food", "water", "doctor", "health", "pain", "sick", "tired", "body", "mental"]),
            (.reminders,      ["remind", "remember", "don't forget", "call", "email", "text", "buy", "pick up", "need to", "have to", "must", "errand"]),
            (.timeManagement, ["deadline", "due", "schedule", "meeting", "appointment", "calendar", "block", "by ", "at ", "monday", "tuesday", "wednesday", "thursday", "friday", "tomorrow", "today", "week"]),
            (.routines,       ["every day", "daily", "every morning", "every night", "habit", "routine", "always", "each", "regular"]),
            (.someday,        ["someday", "one day", "maybe", "wish", "dream", "future", "eventually", "when i", "would love", "want to learn", "bucket"]),
            (.ideas,          ["idea", "what if", "could", "imagine", "project", "build", "create", "design", "app", "concept", "explore"]),
        ]

        for (zone, keywords) in rules {
            if keywords.contains(where: { t.contains($0) }) {
                return zone
            }
        }
        return .captures
    }
}
