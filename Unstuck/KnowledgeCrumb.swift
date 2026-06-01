import Foundation

enum CrumbType {
    case brainFact   // universal neuroscience, never labels
    case pattern     // derived from the user's own data
}

struct KnowledgeCrumb: Identifiable {
    let id = UUID()
    let text: String
    let type: CrumbType
    let positionX: Double   // normalized 0–1 on map canvas
    let positionY: Double
    var discovered = false

    // MARK: - Built-in brain facts
    // Always framed universally — "all brains", never a personal label

    static let brainFacts: [String] = [
        "all brains lose track of objects they can't see. it's not forgetfulness — it's how memory works.",
        "dopamine isn't a reward. it's a prediction signal. it fires when something's about to be good.",
        "the brain processes spatial layouts differently than lists. a map is easier to remember.",
        "novelty triggers dopamine. same reason new apps feel better than old ones.",
        "task-switching costs about 15 minutes of focus each time. it's not laziness — it's neurological tax.",
        "sleep is when the brain washes itself. literally. glymphatic system runs during deep sleep.",
        "all brains have a default mode network — it only goes quiet when you're focused on something external.",
        "urgency creates dopamine. that's why deadlines work even when nothing else does.",
        "the brain can't actually multitask. it time-slices between tasks and calls it multitasking.",
        "external structure (lists, maps, alarms) does the job of working memory so your brain doesn't have to.",
        "boredom is the brain signalling it has capacity. it's not a flaw — it's a feature.",
        "the brain prioritises interesting over important. every time.",
        "\"just start\" works because momentum is easier to continue than to create.",
        "music without lyrics uses auditory cortex differently — leaves language regions free for thinking.",
        "your brain during a \"wall of awful\" is in a threat response. the task isn't scary. the feeling is.",
        "time blindness is a perception issue, not a discipline issue. the brain processes time unevenly.",
        "a 2-minute task estimate makes a task real. without it, the brain treats it as infinite.",
        "the RAS (reticular activating system) filters what you notice. that's why you see your car everywhere.",
    ]

    // MARK: - Factory

    static func makeFacts(count: Int = 5) -> [KnowledgeCrumb] {
        // Seed positions deterministically so crumbs don't jump around
        let positions: [(Double, Double)] = [
            (0.50, 0.40), (0.35, 0.55), (0.65, 0.55),
            (0.50, 0.65), (0.20, 0.38), (0.80, 0.38),
            (0.30, 0.82), (0.70, 0.82), (0.50, 0.28),
        ]
        return brainFacts.prefix(count).enumerated().map { idx, text in
            let pos = positions[idx % positions.count]
            return KnowledgeCrumb(text: text, type: .brainFact,
                                  positionX: pos.0, positionY: pos.1)
        }
    }

    static func makePattern(text: String, positionX: Double, positionY: Double) -> KnowledgeCrumb {
        KnowledgeCrumb(text: text, type: .pattern,
                       positionX: positionX, positionY: positionY)
    }
}
