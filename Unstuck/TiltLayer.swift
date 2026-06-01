import SwiftUI

/// Reads gyro attitude and applies a subtle 3D holographic float.
/// Wrapping map content here means ONLY this view re-renders on tilt —
/// the content inside re-renders only when its own data changes.
///
/// Balance principle (holographic presence + trackpad calm):
///  - Float is RELATIVE to how you're currently holding the phone (drifting rest pose),
///    so lying down / any angle feels neutral — never pegged to absolute gravity.
///  - Gentle magnitude: presence, not a tilt-toy.
struct TiltLayer<Content: View>: View {
    let manualRotation: Angle
    @ViewBuilder let content: () -> Content

    private let motion = MotionAdaptor.shared

    // Drifting neutral pose — recenters on your current hold over a few seconds
    @State private var rest = HolographicState()
    @State private var calibrated = false

    private var h: HolographicState { motion.holographic }

    // Gentle: ~10° max, presence not swing. Calm flattens it; insane cranks it.
    private var maxTilt: Double {
        switch AppSettings.shared.sensory {
        case .calm:   return 0
        case .normal: return 10
        case .insane: return 17
        }
    }

    private var tiltX: Double { ((h.pitch - rest.pitch) * 22).clamped(to: -maxTilt...maxTilt) }
    private var tiltY: Double { (-(h.roll - rest.roll)  * 22).clamped(to: -maxTilt...maxTilt) }
    private var yawRot: Angle { AppSettings.shared.calmMode ? .zero : .degrees((h.yaw - rest.yaw) * 6) }

    var body: some View {
        content()
            .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.28)
            .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.28)
            .rotationEffect(manualRotation + yawRot)
            .onChange(of: h) { _, new in
                if !calibrated {
                    rest = new
                    calibrated = true
                } else {
                    // Slow drift — if you settle into a new posture, neutral follows
                    rest.pitch += 0.015 * (new.pitch - rest.pitch)
                    rest.roll  += 0.015 * (new.roll  - rest.roll)
                    rest.yaw   += 0.015 * (new.yaw   - rest.yaw)
                }
            }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
