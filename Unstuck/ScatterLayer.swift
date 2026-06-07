import SwiftUI

/// The shotgun scatter: when a brain-dump fires, every item bursts from the centre (YOU)
/// and flies on a spring arc to its destination cluster — staggered into a "ratatat",
/// each trailing a colour tracer, landing with the haptic cascade driven by CaptureController.
/// Reduce-Motion: items simply fade in at their clusters (no flight), still satisfying.
struct ScatterLayer: View {
    let shots: [CaptureController.ScatterShot]
    let mapSize: CGSize

    var body: some View {
        ZStack {
            ForEach(shots) { shot in
                ScatterShotView(shot: shot, mapSize: mapSize)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ScatterShotView: View {
    let shot: CaptureController.ScatterShot
    let mapSize: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flew = false

    private var target: CGPoint { CGPoint(x: shot.targetX * mapSize.width, y: shot.targetY * mapSize.height) }
    private var center: CGPoint { CGPoint(x: mapSize.width / 2, y: mapSize.height / 2) }
    private var delay: Double { Double(shot.index) * 0.04 }

    var body: some View {
        ZStack {
            if !reduceMotion {
                // Colour tracer — a streak from centre to the landing spot, visible mid-flight then gone.
                Path { p in p.move(to: center); p.addLine(to: target) }
                    .stroke(
                        LinearGradient(colors: [shot.tint.opacity(0), shot.tint.opacity(0.7)],
                                       startPoint: center == target ? .top : .init(x: center.x / max(mapSize.width, 1),
                                                                                   y: center.y / max(mapSize.height, 1)),
                                       endPoint: .init(x: target.x / max(mapSize.width, 1),
                                                       y: target.y / max(mapSize.height, 1))),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(flew ? 0 : 0.8)
                    .animation(.easeOut(duration: 0.55).delay(delay + 0.18), value: flew)
            }

            // The flying item — a glowing dot in its cluster's colour.
            Circle()
                .fill(shot.tint)
                .frame(width: 11, height: 11)
                .shadow(color: shot.tint.opacity(0.95), radius: flew ? 5 : 16)
                .scaleEffect(flew ? 0.7 : (reduceMotion ? 1.0 : 1.7))
                .opacity(flew ? 0 : 1)                       // fades as it sinks into the cluster
                .position(flew || reduceMotion ? target : center)
        }
        .onAppear {
            withAnimation(reduceMotion
                ? .easeOut(duration: 0.3).delay(delay)
                : .spring(response: 0.55, dampingFraction: 0.68).delay(delay)) {
                flew = true
            }
        }
    }
}
