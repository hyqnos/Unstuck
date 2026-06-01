import Foundation
import Combine
import CoreMotion
import Observation

enum MotionState: Equatable {
    case still, light, active, agitated
}

// @Observable — SwiftUI only re-renders views that read the specific property that changed
@MainActor
@Observable
final class MotionAdaptor {
    private(set) var parameters: MapParameters = .default

    /// Live wrist rotation magnitude (rad/s) — for haptic intensity on fling.
    private(set) var rotationRate: Double = 0.0

    /// Batched holographic state — one @Observable dependency instead of three.
    /// Only updates when angular change exceeds threshold (saves re-renders).
    private(set) var holographic = HolographicState()

    private let motion = CMMotionManager()
    private var samples: [Double] = []
    private let windowSize = 25          // ~1s window at 25Hz
    private var currentState: MotionState = .light
    private var audioFrame = 0           // throttles spatial-audio listener updates
    private var targetParameters: MapParameters = .default
    private var lerpTimer: Timer?

    static let shared = MotionAdaptor()
    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard motion.isAccelerometerAvailable else { return }

        // Handlers fire on the main queue, so we're already main-isolated —
        // assumeIsolated avoids spawning a Task per sample (was ~110 allocs/sec).

        // Accelerometer — motion-state classification (25Hz is plenty)
        motion.accelerometerUpdateInterval = 1.0 / 25.0
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated { self?.process(data) }
        }

        // Device motion — gyro + attitude (30Hz; UI is threshold-gated anyway)
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 30.0
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                MainActor.assumeIsolated { self?.handleMotion(data) }
            }
        }

        // 4 Hz — plenty fast for imperceptible micro-adaptation
        lerpTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lerpStep() }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        motion.stopDeviceMotionUpdates()
        lerpTimer?.invalidate()
    }

    // MARK: - Device motion (gyro + attitude)

    private func handleMotion(_ data: CMDeviceMotion) {
        let r = data.rotationRate
        rotationRate = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)

        let newH = HolographicState(
            pitch: data.attitude.pitch,
            roll:  data.attitude.roll,
            yaw:   data.attitude.yaw
        )
        if newH.meaningfullyDifferent(from: holographic) {
            holographic = newH
        }

        // Spatial-audio listener only needs ~6Hz — throttle hard (every 5th frame)
        audioFrame &+= 1
        if audioFrame % 5 == 0 {
            SpatialAudioService.shared.updateListener(
                pitch: data.attitude.pitch,
                roll:  data.attitude.roll,
                yaw:   data.attitude.yaw
            )
        }
    }

    // MARK: - Accelerometer

    private func process(_ data: CMAccelerometerData) {
        let mag = sqrt(
            data.acceleration.x * data.acceleration.x +
            data.acceleration.y * data.acceleration.y +
            data.acceleration.z * data.acceleration.z
        )
        let dynamic = abs(mag - 1.0)
        samples.append(dynamic)
        if samples.count > windowSize { samples.removeFirst() }
        guard samples.count == windowSize else { return }

        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Double(windowSize))
        let newState = classify(rms: rms)
        guard newState != currentState else { return }
        currentState = newState
        targetParameters = preset(for: newState)
    }

    private func classify(rms: Double) -> MotionState {
        switch rms {
        case ..<0.015: return .still
        case ..<0.06:  return .light
        case ..<0.18:  return .active
        default:       return .agitated
        }
    }

    private func preset(for state: MotionState) -> MapParameters {
        switch state {
        case .still:    return .still
        case .light:    return .light
        case .active:   return .active
        case .agitated: return .agitated
        }
    }

    // MARK: - Threshold lerp — only publish when change is meaningful (> 3%)

    private func lerpStep() {
        guard parameters != targetParameters else { return }
        let next = parameters.lerped(toward: targetParameters, t: 0.12)
        // Skip update if all values moved less than 3% — avoids micro-churn
        if meaningfulChange(from: parameters, to: next) {
            parameters = next
        } else {
            parameters = targetParameters  // snap to target when close
        }
    }

    private func meaningfulChange(from old: MapParameters, to new: MapParameters) -> Bool {
        abs(new.panSensitivity    - old.panSensitivity)    > 0.008 ||
        abs(new.zoomSensitivity   - old.zoomSensitivity)   > 0.008 ||
        abs(new.panBoundsFraction - old.panBoundsFraction) > 0.008
    }
}
