import SwiftUI

/// Rave show that erupts from the YOU stage — built like a real rig, synced to a real beat:
///  • **moving-head laser fans** that sweep in unison and SNAP to a new pose on each beat,
///    beams rendered with a bright-at-source gradient falloff through a volumetric haze
///  • **pyro jets** that fire ON the beat from the stage front (white-hot core, amber sheath,
///    sparks) — bursts, the way real pyro fires, not wavy cartoon flames
///  • an audible **kick drum** + a soft haptic thump on every beat (the beat you can feel)
///
/// One Canvas, additive (.screen) blend, 60fps cap — GPU-cheap, time-limited.
/// Photosensitivity: ALL rhythm (flash, color steps, jets) rides one 1.3 Hz beat with a
/// 2.6 Hz brightness cap (WCAG: < 3 flashes/sec). Reduce Motion gets a calm non-flashing
/// bloom; calm mode never shows this view at all.
struct LaserShowView: View {
    let color: Color          // the milestone's tier color, seeds the palette
    let intensity: Double     // 0…1 — more beams + more jets for bigger wins
    let start: Date
    let duration: Double
    var insane: Bool = false  // crank everything

    // One beat clock for EVERYTHING: ~78 BPM half-time drop feel.
    private static let beatHz = 1.3
    private var beamsPerFan: Int { (insane ? 5 : 3) + Int(intensity * 2) }   // ×4 fans
    private var jetCount: Int    { (insane ? 6 : 3) + Int(intensity * 2) }

    // Rave palette — the tier color plus vivid club hues
    private var palette: [Color] {
        [color,
         Color(red: 1.0, green: 0.1, blue: 0.7),   // magenta
         Color(red: 0.1, green: 0.9, blue: 1.0),   // cyan
         Color(red: 0.5, green: 0.2, blue: 1.0),   // violet
         Color(red: 0.2, green: 1.0, blue: 0.4)]   // laser green
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion { calmGlow } else { strobe }
    }

    private var calmGlow: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { tl in
            let t = tl.date.timeIntervalSince(start)
            let p = max(0, min(1, t / max(0.1, duration)))
            let a = sin(p * .pi) * 0.45            // one gentle bell — up then down
            RadialGradient(colors: [color.opacity(a), .clear],
                           center: .center, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var strobe: some View {
        // 60fps cap — sweeping beams read identically at 60, and this is the
        // heaviest Canvas in the app (fires on every completion in insane mode).
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                guard t >= 0, t < duration else { return }

                let env  = envelope(t)
                // Brightness pulse capped at 2.6 Hz (photosensitivity), peaking once per beat.
                let beat = pow(max(0, sin(t * .pi * 2 * Self.beatHz)), 6)
                let beatIndex = Int(t * Self.beatHz)
                let stage = CGPoint(x: size.width / 2, y: size.height / 2)
                let reach = hypot(size.width, size.height)

                drawHaze(ctx, size, stage: stage, env: env, beat: beat)
                drawPyro(ctx, size, t: t, env: env, beat: beat, beatIndex: beatIndex)
                drawLasers(ctx, stage: stage, reach: reach, t: t, env: env,
                           beat: beat, beatIndex: beatIndex)
            }
            .blendMode(.screen)        // additive — beams glow over the dark space
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        // The beat you can HEAR and FEEL: a kick + a soft haptic thump on every beat peak.
        .task(id: start) {
            guard !AppSettings.shared.calmMode else { return }
            let period = 1.0 / Self.beatHz
            var next = start.addingTimeInterval(period * 0.25)   // first peak of sin^6
            let end = start.addingTimeInterval(duration)
            while !Task.isCancelled {
                let wait = next.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, Date() < end else { break }
                SpatialAudioService.shared.playBlip(.kick, atX: 0.5, y: 0.5)
                HapticEngine.shared.settle()
                next = next.addingTimeInterval(period)
            }
        }
    }

    // Deterministic hash noise — per-beat "randomness" with zero RNG state.
    private func prand(_ a: Int, _ b: Int) -> Double {
        let s = sin(Double(a) * 127.1 + Double(b) * 311.7) * 43758.5453
        return s - floor(s)
    }

    // MARK: - Haze (volumetric fog the beams live in — this is what sells "real")

    private func drawHaze(_ ctx: GraphicsContext, _ size: CGSize, stage: CGPoint,
                          env: Double, beat: Double) {
        let a = env * (0.05 + 0.05 * beat)
        let r = max(size.width, size.height) * 0.75
        ctx.fill(
            Path(ellipseIn: CGRect(x: stage.x - r, y: stage.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(Gradient(colors: [.white.opacity(a), .clear]),
                                  center: stage, startRadius: 0, endRadius: r)
        )
        // Floor wash — the stage-front glow the jets punch through
        let wash = CGRect(x: 0, y: size.height - 130, width: size.width, height: 130)
        ctx.fill(Path(wash), with: .linearGradient(
            Gradient(colors: [.clear, color.opacity(env * (0.05 + 0.07 * beat))]),
            startPoint: CGPoint(x: 0, y: wash.minY), endPoint: CGPoint(x: 0, y: wash.maxY)))
    }

    // MARK: - Lasers — four moving-head fans that sweep in unison and snap per beat

    private func drawLasers(_ ctx: GraphicsContext, stage: CGPoint, reach: CGFloat,
                            t: Double, env: Double, beat: Double, beatIndex: Int) {
        let bright = env * (0.45 + 0.55 * beat)
        let n = beamsPerFan
        let spread = 0.42 + 0.18 * intensity            // fan width (radians)

        for fan in 0..<4 {
            // Each fan aims at a quadrant, sweeps sinusoidally IN UNISON, and snaps to a
            // new pose on every beat — the signature moving-head move.
            let aim = Double(fan) * .pi / 2 + .pi / 4
            let sweep = sin(t * 0.9 + Double(fan) * 1.6) * 0.5
            let snap  = (prand(beatIndex, fan) - 0.5) * 0.9
            let center = aim + sweep + snap
            // Color steps on the beat — the whole fan changes hue on the drop.
            let c = palette[(beatIndex + fan) % palette.count]

            for i in 0..<n {
                let angle = center + (Double(i) - Double(n - 1) / 2) / Double(max(1, n - 1)) * spread
                let end = CGPoint(x: stage.x + CGFloat(cos(angle)) * reach,
                                  y: stage.y + CGFloat(sin(angle)) * reach)
                var beam = Path(); beam.move(to: stage); beam.addLine(to: end)

                // Bright at the source, dissolving into the haze — gradient falloff.
                let falloff = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [c.opacity(bright * 0.85), c.opacity(bright * 0.25), .clear]),
                    startPoint: stage, endPoint: end)
                ctx.stroke(beam, with: falloff, lineWidth: 8)        // soft volumetric body
                ctx.stroke(beam, with: .linearGradient(
                    Gradient(colors: [.white.opacity(bright * 0.9), c.opacity(bright * 0.5), .clear]),
                    startPoint: stage, endPoint: end), lineWidth: 1.4)   // hot core
            }
        }

        // Stage glow at the center — swells on the beat
        let r: CGFloat = 60 + 26 * beat
        ctx.fill(
            Path(ellipseIn: CGRect(x: stage.x - r, y: stage.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(Gradient(colors: [.white.opacity(bright * 0.55), .clear]),
                                  center: stage, startRadius: 0, endRadius: r)
        )
    }

    // MARK: - Pyro jets — fire ON the beat from the stage front (bursts, like real pyro)

    private func drawPyro(_ ctx: GraphicsContext, _ size: CGSize,
                          t: Double, env: Double, beat: Double, beatIndex: Int) {
        let baseY = size.height + 6
        for k in 0..<jetCount {
            // Normal shows alternate columns per beat; insane fires the whole line.
            guard insane || (beatIndex + k) % 2 == 0 else { continue }

            let x = (Double(k) + 0.5) / Double(jetCount) * size.width
            let kick = pow(beat, 0.7)                         // the burst envelope
            guard kick > 0.02 else { continue }
            let h = (120 + 170 * intensity) * kick * (0.8 + 0.4 * prand(k, beatIndex))
            let cx = CGFloat(x), topY = baseY - CGFloat(h)
            let lean = CGFloat((prand(k, beatIndex &+ 7) - 0.5) * 18)   // slight per-burst lean

            // Amber sheath → white-hot core (capsule columns, not blobs)
            let sheath = CGRect(x: cx - 13 + lean * 0.4, y: topY, width: 26, height: CGFloat(h))
            ctx.fill(Path(roundedRect: sheath, cornerRadius: 13), with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.1).opacity(env * 0.0),
                                  Color(red: 1.0, green: 0.55, blue: 0.1).opacity(env * 0.55 * kick)]),
                startPoint: CGPoint(x: cx, y: topY), endPoint: CGPoint(x: cx, y: baseY)))
            let core = CGRect(x: cx - 4.5 + lean * 0.2, y: topY + CGFloat(h) * 0.15, width: 9,
                              height: CGFloat(h) * 0.85)
            ctx.fill(Path(roundedRect: core, cornerRadius: 4.5), with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.7).opacity(env * 0.25 * kick),
                                  .white.opacity(env * 0.85 * kick)]),
                startPoint: CGPoint(x: cx, y: topY), endPoint: CGPoint(x: cx, y: baseY)))

            // Sparks above the tip
            for s in 0..<3 {
                let sx = cx + lean + CGFloat((prand(k &+ s, beatIndex) - 0.5) * 34)
                let sy = topY - CGFloat(8 + prand(s, beatIndex &+ k) * 26) * CGFloat(kick)
                let sr = CGFloat(1.2 + prand(s &+ 3, k) * 1.6)
                ctx.fill(Path(ellipseIn: CGRect(x: sx - sr, y: sy - sr, width: sr * 2, height: sr * 2)),
                         with: .color(Color(red: 1.0, green: 0.8, blue: 0.4).opacity(env * 0.8 * kick)))
            }
        }
    }

    // Fast fade-in, hold, fade-out
    private func envelope(_ t: Double) -> Double {
        let fadeIn  = min(1, t / 0.2)
        let fadeOut = t > duration - 0.7 ? max(0, (duration - t) / 0.7) : 1
        return fadeIn * fadeOut
    }
}
