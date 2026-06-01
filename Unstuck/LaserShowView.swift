import SwiftUI

/// Rave laser + flame show that erupts from the YOU stage at the center of the web
/// when a big milestone lands. One Canvas, additive (.screen) blend — GPU-cheap,
/// time-limited. Beat-synced strobe. Intensity scales with the milestone tier.
struct LaserShowView: View {
    let color: Color          // the milestone's tier color, seeds the palette
    let intensity: Double     // 0…1 — more beams + taller flames for bigger wins
    let start: Date
    let duration: Double
    var insane: Bool = false  // crank everything

    private var beamCount: Int  { (insane ? 16 : 6) + Int(intensity * 10) }   // up to 26
    private var flameCount: Int { (insane ? 9 : 5) + Int(intensity * 5) }     // up to 15
    private var beatRate: Double { insane ? 1.6 : 1.0 }

    // Rave palette — the tier color plus vivid club hues
    private var palette: [Color] {
        [color,
         Color(red: 1.0, green: 0.1, blue: 0.7),   // magenta
         Color(red: 0.1, green: 0.9, blue: 1.0),   // cyan
         Color(red: 0.5, green: 0.2, blue: 1.0),   // violet
         Color(red: 0.2, green: 1.0, blue: 0.4)]   // laser green
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                guard t >= 0, t < duration else { return }

                let env  = envelope(t)
                // ~128 BPM kick — sharp pulses (faster in insane mode)
                let beat = pow(max(0, sin(t * .pi * (128.0 / 60.0) * 2 * beatRate)), 6)
                let stage = CGPoint(x: size.width / 2, y: size.height / 2)
                let reach = hypot(size.width, size.height)

                drawFlames(ctx, size, t: t, env: env)
                drawLasers(ctx, stage: stage, reach: reach, t: t, env: env, beat: beat)
            }
            .blendMode(.screen)        // additive — beams glow over the dark space
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Lasers (sweep from the stage)

    private func drawLasers(_ ctx: GraphicsContext, stage: CGPoint, reach: CGFloat,
                            t: Double, env: Double, beat: Double) {
        let bright = env * (0.35 + 0.65 * beat)
        for i in 0..<beamCount {
            let base = Double(i) / Double(beamCount) * .pi * 2
            let sweep = sin(t * (1.1 + Double(i % 3) * 0.4) + Double(i)) * 0.6
            let angle = base + sweep
            let end = CGPoint(x: stage.x + CGFloat(cos(angle)) * reach,
                              y: stage.y + CGFloat(sin(angle)) * reach)
            let c = palette[i % palette.count]

            // Wide soft glow
            var glow = Path(); glow.move(to: stage); glow.addLine(to: end)
            ctx.stroke(glow, with: .color(c.opacity(bright * 0.18)), lineWidth: 9)
            // Bright core
            var core = Path(); core.move(to: stage); core.addLine(to: end)
            ctx.stroke(core, with: .color(c.opacity(bright * 0.9)), lineWidth: 1.6)
        }
        // Stage glow at the center
        let r: CGFloat = 70
        ctx.fill(
            Path(ellipseIn: CGRect(x: stage.x - r, y: stage.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(Gradient(colors: [.white.opacity(bright * 0.5), .clear]),
                                  center: stage, startRadius: 0, endRadius: r)
        )
    }

    // MARK: - Flames (lick upward from the crowd / stage front)

    private func drawFlames(_ ctx: GraphicsContext, _ size: CGSize, t: Double, env: Double) {
        let baseY = size.height
        for k in 0..<flameCount {
            let x = (Double(k) + 0.5) / Double(flameCount) * size.width
            let flick = 0.55 + 0.45 * sin(t * 9 + Double(k) * 1.7)
            let h = (90 + 150 * intensity) * flick
            let w = 70.0 * (0.7 + 0.3 * flick)
            let cx = CGFloat(x)
            let topY = baseY - CGFloat(h)

            let rect = CGRect(x: cx - CGFloat(w) / 2, y: topY,
                              width: CGFloat(w), height: CGFloat(h) * 1.2)
            ctx.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.85, blue: 0.3).opacity(env * 0.5 * flick),
                        Color(red: 1.0, green: 0.35, blue: 0.05).opacity(env * 0.35 * flick),
                        .clear
                    ]),
                    center: CGPoint(x: cx, y: baseY),
                    startRadius: 0, endRadius: CGFloat(h)
                )
            )
        }
    }

    // Fast fade-in, hold, fade-out
    private func envelope(_ t: Double) -> Double {
        let fadeIn  = min(1, t / 0.2)
        let fadeOut = t > duration - 0.7 ? max(0, (duration - t) / 0.7) : 1
        return fadeIn * fadeOut
    }
}
