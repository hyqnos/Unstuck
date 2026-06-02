import SwiftUI

/// 🥚 Spider-web easter egg. A web *thwips* out from YOU (the centre of the map)
/// across the whole screen, holds a beat, then fades — on theme, since the brain
/// map already is a web of nodes. Triggered by a magic word ("thwip", "spiderman").
/// Purely cosmetic, never interactive, and the trigger skips it in calm mode.
struct WebShotView: View {
    let start: Date
    var spokes: Int = 12
    var rings: Int = 6

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = hypot(size.width, size.height) / 2

                // shoot out (ease-out) → hold → fade
                let grow  = min(1, t / 0.36)
                let eased = 1 - pow(1 - grow, 3)
                let fade  = t < 0.9 ? 1 : max(0, 1 - (t - 0.9) / 0.7)
                guard fade > 0 else { return }

                let R = maxR * eased
                let alpha = 0.85 * fade
                let web = Color(red: 0.85, green: 0.92, blue: 1.0)

                func pt(_ i: Int, _ r: Double) -> CGPoint {
                    let a = Double(i) / Double(spokes) * 2 * .pi - .pi / 2
                    return CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                }

                // Radial spokes
                var spokePath = Path()
                for i in 0..<spokes { spokePath.move(to: center); spokePath.addLine(to: pt(i, R)) }
                ctx.stroke(spokePath, with: .color(web.opacity(alpha)), lineWidth: 1.4)

                // Concentric threads, sagged inward between spokes (the classic web curve)
                var ringPath = Path()
                for ring in 1...rings {
                    let rr = R * Double(ring) / Double(rings)
                    for i in 0..<spokes {
                        let p0 = pt(i, rr)
                        let p1 = pt((i + 1) % spokes, rr)
                        let sag0 = pt(i, rr * 0.84)
                        let sag1 = pt((i + 1) % spokes, rr * 0.84)
                        let ctrl = CGPoint(x: (sag0.x + sag1.x) / 2, y: (sag0.y + sag1.y) / 2)
                        ringPath.move(to: p0)
                        ringPath.addQuadCurve(to: p1, control: ctrl)
                    }
                }
                ctx.stroke(ringPath, with: .color(web.opacity(alpha * 0.8)), lineWidth: 1.1)

                // A soft glint where the web anchors on YOU
                let g = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: g), with: .color(web.opacity(alpha)))
            }
            .blendMode(.screen)
            .ignoresSafeArea()
        }
    }
}
