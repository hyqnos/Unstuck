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
    private let stars: [StarData] = (0..<130).map { _ in
        StarData(
            x: .random(in: 0...1),
            y: .random(in: 0...1),
            size: .random(in: 0.7...2.4),
            baseOpacity: .random(in: 0.3...0.9),
            phase: .random(in: 0...(Double.pi * 2)),
            speed: .random(in: 0.25...1.0)
        )
    }

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

                // All stars in ONE draw call per frame — Canvas is a single Metal layer.
                // Capped at 30fps: twinkling needs no more, and every glass surface
                // re-samples this backdrop, so halving its rate halves glass cost.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
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
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
