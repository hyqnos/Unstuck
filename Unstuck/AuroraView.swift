import SwiftUI

/// Northern-lights mood indicator — a flowing aurora across the top of the sky.
/// Its colors ARE the mood readout (green=ready, blue=hyperfocus, amber=low, dim=overwhelm).
/// GPU-native MeshGradient + a low-rate timeline = cheap. Lives ABOVE the glass,
/// so it never adds to glass backdrop-sampling cost.
struct AuroraView: View {
    let colors: [Color]
    let intensity: Double

    var body: some View {
        // 20fps is plenty for a slow aurora drift — keeps it cheap
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3, height: 3,
                points: meshPoints(t),
                colors: meshColors(),
                smoothsColors: true
            )
            .blur(radius: 24)
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        // Fade out toward the bottom so it reads as sky-glow, not a band
        .mask(
            LinearGradient(
                colors: [.white, .white.opacity(0.5), .clear],
                startPoint: .top, endPoint: .bottom
            )
        )
        .opacity(intensity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 2.5), value: intensity)
    }

    // 3×3 mesh — top + bottom rows pinned, middle row flows horizontally
    private func meshPoints(_ t: TimeInterval) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.4)) * 0.18
        let b = Float(cos(t * 0.33)) * 0.18
        let c = Float(sin(t * 0.5 + 1)) * 0.15
        return [
            [0.0, 0.0],            [0.5 + a * 0.3, 0.0],      [1.0, 0.0],
            [0.0, 0.5 + b],        [0.5 + c, 0.45 + a],       [1.0, 0.5 - b],
            [0.0, 1.0],            [0.5 - c * 0.3, 1.0],      [1.0, 1.0],
        ]
    }

    private func meshColors() -> [Color] {
        let p = colors
        guard p.count >= 3 else {
            return Array(repeating: .clear, count: 9)
        }
        // Top row brightest (the glow source), bottom row fades to clear
        return [
            p[0],                  p[1],                  p[2],
            p[1].opacity(0.7),     p[2].opacity(0.6),     p[0].opacity(0.7),
            .clear,                .clear,                .clear,
        ]
    }
}
