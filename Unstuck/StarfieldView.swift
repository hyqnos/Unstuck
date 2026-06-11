import SwiftUI

private struct StarData {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let baseOpacity: Double
    let phase: Double   // twinkle phase offset
    let speed: Double   // twinkle speed
}

/// Sky palette by time of day (+ a subtle seasonal nudge). The map quietly looks
/// different morning vs night and across seasons, so it "checks different" when you
/// return — novelty engine. Shifts on its own; never signals anything to do.
struct SkyPalette {
    let top: Color, bottom: Color, nebulaA: Color, nebulaB: Color
    let starTint: Color, starBrightness: Double

    static func now(_ date: Date = Date()) -> SkyPalette {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.month, from: date)
        // gentle seasonal warmth: summer warmer, winter cooler
        let warm = (6...8).contains(m) ? 0.04 : (m == 12 || m <= 2 ? -0.02 : 0.0)
        switch h {
        case 5..<9:    // dawn — deep indigo, a rose hint
            return SkyPalette(top: Color(red: 0.10 + warm, green: 0.06, blue: 0.16),
                              bottom: Color(red: 0.02, green: 0.02, blue: 0.06),
                              nebulaA: Color(red: 0.35, green: 0.12, blue: 0.30).opacity(0.10),
                              nebulaB: Color(red: 0.10, green: 0.18, blue: 0.40).opacity(0.08),
                              starTint: Color(red: 1.0, green: 0.95, blue: 0.90), starBrightness: 0.85)
        case 9..<17:   // day — clearer, cooler blue, brightest stars
            return SkyPalette(top: Color(red: 0.05, green: 0.07, blue: 0.16 + warm),
                              bottom: Color(red: 0.01, green: 0.02, blue: 0.07),
                              nebulaA: Color(red: 0.12, green: 0.20, blue: 0.45).opacity(0.10),
                              nebulaB: Color(red: 0.10, green: 0.25, blue: 0.40).opacity(0.07),
                              starTint: .white, starBrightness: 1.0)
        case 17..<22:  // dusk — warm amber / violet wash
            return SkyPalette(top: Color(red: 0.14 + warm, green: 0.07, blue: 0.12),
                              bottom: Color(red: 0.02, green: 0.02, blue: 0.05),
                              nebulaA: Color(red: 0.40, green: 0.18, blue: 0.20).opacity(0.10),
                              nebulaB: Color(red: 0.25, green: 0.10, blue: 0.30).opacity(0.08),
                              starTint: Color(red: 1.0, green: 0.92, blue: 0.82), starBrightness: 0.9)
        default:       // night — deepest, coolest, dimmer
            return SkyPalette(top: Color(red: 0.03, green: 0.03, blue: 0.10),
                              bottom: Color(red: 0.005, green: 0.005, blue: 0.03),
                              nebulaA: Color(red: 0.18, green: 0.10, blue: 0.38).opacity(0.09),
                              nebulaB: Color(red: 0.05, green: 0.15, blue: 0.35).opacity(0.08),
                              starTint: Color(red: 0.85, green: 0.90, blue: 1.0), starBrightness: 0.75)
        }
    }
}

struct StarfieldView: View {
    private let palette = SkyPalette.now()
    private let stars: [StarData]
    private let age: Double   // Progression.mapAge — the sky deepens with cumulative use

    /// The map AGES: more time + more captured thoughts → a denser sky, a faint growth
    /// nebula, and (at quiet thresholds) small new constellations. Never announced —
    /// one day you just notice it looks deeper. The novelty-death counterweight.
    init() {
        let age = Progression.shared.mapAge
        self.age = age
        self.stars = (0..<(130 + Int(age * 90))).map { _ in
            StarData(
                x: .random(in: 0...1),
                y: .random(in: 0...1),
                size: .random(in: 0.7...2.4),
                baseOpacity: .random(in: 0.3...0.9),
                phase: .random(in: 0...(Double.pi * 2)),
                speed: .random(in: 0.25...1.0)
            )
        }
    }

    /// Decorative mini-constellations (normalized coords, kept to edges away from the
    /// clusters/YOU) that fade in as the sky matures. Quiet milestones in the glass.
    private static let grownConstellations: [(threshold: Double, points: [CGPoint])] = [
        (0.25, [CGPoint(x: 0.07, y: 0.06), CGPoint(x: 0.13, y: 0.10), CGPoint(x: 0.19, y: 0.07),
                CGPoint(x: 0.16, y: 0.14)]),                                        // the anchor
        (0.50, [CGPoint(x: 0.88, y: 0.30), CGPoint(x: 0.94, y: 0.35), CGPoint(x: 0.90, y: 0.42),
                CGPoint(x: 0.84, y: 0.38), CGPoint(x: 0.88, y: 0.30)]),             // the kite
        (0.75, [CGPoint(x: 0.08, y: 0.86), CGPoint(x: 0.14, y: 0.80), CGPoint(x: 0.20, y: 0.84),
                CGPoint(x: 0.26, y: 0.79), CGPoint(x: 0.31, y: 0.85)]),             // the crown
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Deep space gradient
                LinearGradient(
                    colors: [palette.top, palette.bottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Faint nebula blobs — static, cheap
                Circle()
                    .fill(palette.nebulaA)
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: -geo.size.width * 0.15, y: -geo.size.height * 0.1)
                    .blur(radius: 60)
                    .allowsHitTesting(false)

                Circle()
                    .fill(palette.nebulaB)
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: geo.size.width * 0.2, y: geo.size.height * 0.2)
                    .blur(radius: 50)
                    .allowsHitTesting(false)

                // The growth nebula — invisible on day one, a faint teal-violet bloom as
                // the sky matures. The slowest reward in the app.
                if age > 0.05 {
                    Circle()
                        .fill(Color(red: 0.25, green: 0.45, blue: 0.55).opacity(0.11 * age))
                        .frame(width: geo.size.width * (0.5 + 0.3 * age))
                        .offset(x: -geo.size.width * 0.25, y: geo.size.height * 0.32)
                        .blur(radius: 55)
                        .allowsHitTesting(false)
                }

                // All stars in ONE draw call per frame — Canvas is a single Metal layer.
                // Capped at 24fps: twinkling needs no more, and every glass surface
                // re-samples this backdrop, so trimming its rate trims glass cost too.
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        for star in stars {
                            let twinkle = sin(t * star.speed + star.phase) * 0.5 + 0.5
                            let opacity = star.baseOpacity * (0.35 + 0.65 * twinkle)
                            let cx = star.x * size.width
                            let cy = star.y * size.height
                            let r = star.size / 2
                            let rect = CGRect(x: cx - r, y: cy - r, width: star.size, height: star.size)
                            ctx.fill(
                                Path(ellipseIn: rect),
                                with: .color(palette.starTint.opacity(opacity * palette.starBrightness))
                            )
                        }

                        // Grown constellations — each fades in once its threshold is crossed.
                        for c in Self.grownConstellations where age > c.threshold {
                            let reveal = min(1, (age - c.threshold) / 0.08)
                            let a = 0.32 * reveal * palette.starBrightness
                            var lines = Path()
                            let pts = c.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                            lines.move(to: pts[0])
                            for p in pts.dropFirst() { lines.addLine(to: p) }
                            ctx.stroke(lines, with: .color(palette.starTint.opacity(a * 0.5)), lineWidth: 0.7)
                            for p in pts {
                                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.1, y: p.y - 1.1, width: 2.2, height: 2.2)),
                                         with: .color(palette.starTint.opacity(a)))
                            }
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
