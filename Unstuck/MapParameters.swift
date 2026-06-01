import SwiftUI

// MARK: - Holographic state (batched gyro attitude)

struct HolographicState: Equatable {
    var pitch: Double = 0   // forward/back tilt (rad)
    var roll:  Double = 0   // left/right tilt (rad)
    var yaw:   Double = 0   // turning in place (rad)

    // Only trigger re-render when angle changes more than ~0.8°
    func meaningfullyDifferent(from other: HolographicState) -> Bool {
        abs(pitch - other.pitch) > 0.014 ||
        abs(roll  - other.roll)  > 0.014 ||
        abs(yaw   - other.yaw)   > 0.014
    }
}

// MARK: - Map parameters
struct MapParameters: Equatable {
    /// Multiplier on how far the pan gesture moves the canvas (0.7 = dampened, 1.2 = amplified)
    var panSensitivity: CGFloat
    /// Spring response for pan release — lower = snappier
    var panSpringResponse: Double
    /// Spring damping for pan release — higher = less bounce
    var panSpringDamping: Double
    /// Max pan bounds multiplier (fraction of screen size each direction)
    var panBoundsFraction: CGFloat
    /// Pinch sensitivity multiplier
    var zoomSensitivity: CGFloat
    /// Cluster breathing cycle multiplier (1.0 = normal, 1.4 = faster)
    var breathSpeedMultiplier: Double
    /// Cluster breathing amplitude — how much it scales
    var breathAmplitude: CGFloat
    /// Minimum drag distance before pan fires (larger = ignore micro-tremor)
    var panMinimumDistance: CGFloat

    // MARK: - Presets

    static let `default` = MapParameters(
        panSensitivity:      1.0,
        panSpringResponse:   0.35,
        panSpringDamping:    0.75,
        panBoundsFraction:   0.6,
        zoomSensitivity:     1.0,
        breathSpeedMultiplier: 1.0,
        breathAmplitude:     1.018,
        panMinimumDistance:  8
    )

    /// Almost no movement — precise, responsive
    static let still = MapParameters(
        panSensitivity:      1.15,
        panSpringResponse:   0.28,
        panSpringDamping:    0.7,
        panBoundsFraction:   0.7,
        zoomSensitivity:     1.1,
        breathSpeedMultiplier: 0.75,
        breathAmplitude:     1.012,
        panMinimumDistance:  6
    )

    /// Light hand movement — normal usage
    static let light = `default`

    /// Walking / active — damp it down so the map doesn't fly around
    static let active = MapParameters(
        panSensitivity:      0.75,
        panSpringResponse:   0.45,
        panSpringDamping:    0.88,
        panBoundsFraction:   0.5,
        zoomSensitivity:     0.8,
        breathSpeedMultiplier: 1.35,
        breathAmplitude:     1.025,
        panMinimumDistance:  14
    )

    /// Shaky / agitated — maximum stability
    static let agitated = MapParameters(
        panSensitivity:      0.55,
        panSpringResponse:   0.55,
        panSpringDamping:    0.95,
        panBoundsFraction:   0.4,
        zoomSensitivity:     0.6,
        breathSpeedMultiplier: 1.6,
        breathAmplitude:     1.03,
        panMinimumDistance:  20
    )

    // MARK: - Smooth interpolation between states

    func lerped(toward target: MapParameters, t: CGFloat) -> MapParameters {
        MapParameters(
            panSensitivity:       lerp(panSensitivity, target.panSensitivity, t),
            panSpringResponse:    Double(lerp(CGFloat(panSpringResponse), CGFloat(target.panSpringResponse), t)),
            panSpringDamping:     Double(lerp(CGFloat(panSpringDamping), CGFloat(target.panSpringDamping), t)),
            panBoundsFraction:    lerp(panBoundsFraction, target.panBoundsFraction, t),
            zoomSensitivity:      lerp(zoomSensitivity, target.zoomSensitivity, t),
            breathSpeedMultiplier: Double(lerp(CGFloat(breathSpeedMultiplier), CGFloat(target.breathSpeedMultiplier), t)),
            breathAmplitude:      lerp(breathAmplitude, target.breathAmplitude, t),
            panMinimumDistance:   lerp(panMinimumDistance, target.panMinimumDistance, t)
        )
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}
