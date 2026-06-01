import SwiftUI

struct MoodTheme {
    // Starfield
    var starOpacity: Double        // overall star brightness
    var nebulaOpacity: Double      // nebula blob opacity

    // Cluster visibility
    var clusterOpacity: Double     // non-priority clusters
    var priorityClusterOpacity: Double  // most urgent cluster

    // Tint overlay on the whole map
    var tintColor: Color
    var tintOpacity: Double

    // "YOU" label
    var youOpacity: Double

    // Animation speed modifier
    var animationSpeedMultiplier: Double  // 1.0 = normal

    // Capture bar visibility
    var captureBarOpacity: Double

    // Nudge message (nil = no nudge)
    var nudge: String?

    // Northern-lights mood indicator — the aurora's hue IS the mood readout
    var auroraColors: [Color]
    var auroraIntensity: Double

    // MARK: - Presets

    static let ready = MoodTheme(
        starOpacity: 1.0,
        nebulaOpacity: 1.0,
        clusterOpacity: 1.0,
        priorityClusterOpacity: 1.0,
        tintColor: .clear,
        tintOpacity: 0,
        youOpacity: 0.18,
        animationSpeedMultiplier: 1.0,
        captureBarOpacity: 1.0,
        nudge: nil,
        auroraColors: [   // classic green-teal aurora — calm, awake, ready
            Color(red: 0.1, green: 0.9, blue: 0.55),
            Color(red: 0.15, green: 0.7, blue: 0.85),
            Color(red: 0.35, green: 0.85, blue: 0.6),
        ],
        auroraIntensity: 0.5
    )

    static let lowBattery = MoodTheme(
        starOpacity: 0.5,
        nebulaOpacity: 0.6,
        clusterOpacity: 0.45,
        priorityClusterOpacity: 0.85,
        tintColor: Color(red: 1.0, green: 0.75, blue: 0.4),  // warm amber
        tintOpacity: 0.06,
        youOpacity: 0.12,
        animationSpeedMultiplier: 0.6,
        captureBarOpacity: 0.8,
        nudge: nil,
        auroraColors: [   // warm amber-rose — dusk, winding down
            Color(red: 1.0, green: 0.55, blue: 0.35),
            Color(red: 0.95, green: 0.4, blue: 0.5),
            Color(red: 1.0, green: 0.7, blue: 0.4),
        ],
        auroraIntensity: 0.4
    )

    static let overwhelm = MoodTheme(
        starOpacity: 0.18,
        nebulaOpacity: 0.2,
        clusterOpacity: 0.12,
        priorityClusterOpacity: 1.0,
        tintColor: .clear,
        tintOpacity: 0,
        youOpacity: 0.3,
        animationSpeedMultiplier: 0.4,
        captureBarOpacity: 1.0,
        nudge: "one thing.",
        auroraColors: [   // near-gone, single soft band — minimal, quiet
            Color(red: 0.4, green: 0.55, blue: 0.7),
            Color(red: 0.3, green: 0.45, blue: 0.6),
            Color(red: 0.4, green: 0.55, blue: 0.7),
        ],
        auroraIntensity: 0.12
    )

    static let hyperfocus = MoodTheme(
        starOpacity: 0.25,
        nebulaOpacity: 0.15,
        clusterOpacity: 0.2,
        priorityClusterOpacity: 0.7,
        tintColor: Color(red: 0.3, green: 0.5, blue: 1.0),  // cool blue
        tintOpacity: 0.04,
        youOpacity: 0.08,
        animationSpeedMultiplier: 0.3,
        captureBarOpacity: 0.5,
        nudge: "still here.",
        auroraColors: [   // electric blue-violet — deep, locked-in flow
            Color(red: 0.3, green: 0.5, blue: 1.0),
            Color(red: 0.6, green: 0.3, blue: 1.0),
            Color(red: 0.35, green: 0.6, blue: 1.0),
        ],
        auroraIntensity: 0.45
    )

    static func theme(for mode: BrainMode) -> MoodTheme {
        switch mode {
        case .ready:      return .ready
        case .lowBattery: return .lowBattery
        case .overwhelm:  return .overwhelm
        case .hyperfocus: return .hyperfocus
        }
    }
}
