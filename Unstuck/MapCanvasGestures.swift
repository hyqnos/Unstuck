import SwiftUI

/// The trackpad-style canvas gestures: pan (with inertia + rubber-band settle),
/// pinch-zoom, and double-tap reset. Owns its own gesture state so BrainMapView
/// doesn't. Rotation stays in the view — its live value feeds the tilt layer.
struct MapCanvasGestures: ViewModifier {
    @Binding var panOffset: CGSize
    @Binding var userScale: CGFloat
    @Binding var mapRotation: Angle
    let size: CGSize

    @GestureState private var gesturePan: CGSize = .zero
    @GestureState private var gestureMagnify: CGFloat = 1.0

    private let motion = MotionAdaptor.shared

    private var clampedScale: CGFloat {
        (userScale * gestureMagnify).clamped(to: 0.4...2.5)
    }

    func body(content: Content) -> some View {
        content
            .offset(displayedPan())
            .scaleEffect(clampedScale)
            // 1. Pan — trackpad scroll with inertia + rubber-band settle
            .gesture(
                DragGesture(minimumDistance: 8)
                    .updating($gesturePan) { v, state, _ in
                        let s = motion.parameters.panSensitivity
                        state = CGSize(width: v.translation.width * s,
                                      height: v.translation.height * s)
                    }
                    .onEnded { v in
                        let p = motion.parameters
                        let sens = p.panSensitivity
                        let inertiaX = v.velocity.width  * 0.12 * sens
                        let inertiaY = v.velocity.height * 0.12 * sens
                        let dx = v.translation.width  * sens + inertiaX
                        let dy = v.translation.height * sens + inertiaY
                        let bounds = p.panBoundsFraction
                        let newX = (panOffset.width  + dx).clamped(to: -size.width  * bounds ... size.width  * bounds)
                        let newY = (panOffset.height + dy).clamped(to: -size.height * bounds ... size.height * bounds)
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                            panOffset = CGSize(width: newX, height: newY)
                        }
                    }
            )
            // 2. Pinch to zoom — anchored, smooth
            .gesture(
                MagnifyGesture()
                    .updating($gestureMagnify) { v, state, _ in
                        state = 1 + (v.magnification - 1) * motion.parameters.zoomSensitivity
                    }
                    .onEnded { v in
                        let adjusted = 1 + (v.magnification - 1) * motion.parameters.zoomSensitivity
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            userScale = (userScale * adjusted).clamped(to: 0.4...2.5)
                        }
                    }
            )
            // 3. Double-tap empty space — reset pan / zoom / rotation to default
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                    panOffset   = .zero
                    userScale   = 1.0
                    mapRotation = .zero
                }
                HapticEngine.shared.complete()
            }
    }

    // Live pan with macOS-style rubber-banding past the edges
    private func displayedPan() -> CGSize {
        let bounds = motion.parameters.panBoundsFraction
        let limitX = size.width  * bounds
        let limitY = size.height * bounds
        let rawX = panOffset.width  + gesturePan.width
        let rawY = panOffset.height + gesturePan.height
        return CGSize(
            width:  rubberBand(rawX, limit: limitX, dimension: size.width),
            height: rubberBand(rawY, limit: limitY, dimension: size.height)
        )
    }

    private func rubberBand(_ value: CGFloat, limit: CGFloat, dimension: CGFloat) -> CGFloat {
        let c: CGFloat = 0.55
        if value > limit {
            let over = value - limit
            return limit + (over * dimension * c) / (dimension + c * over)
        } else if value < -limit {
            let over = -limit - value
            return -limit - (over * dimension * c) / (dimension + c * over)
        }
        return value
    }
}

extension View {
    func mapCanvasGestures(panOffset: Binding<CGSize>, userScale: Binding<CGFloat>,
                           mapRotation: Binding<Angle>, size: CGSize) -> some View {
        modifier(MapCanvasGestures(panOffset: panOffset, userScale: userScale,
                                   mapRotation: mapRotation, size: size))
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
