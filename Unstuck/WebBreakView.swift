import SwiftUI

/// "The wall came down." On finishing a dreaded task, a web forms over the screen, strains,
/// then SHATTERS — spokes snap, rings break into gaps, shards fly outward — synced to the
/// `HapticEngine.breakthrough()` crack. The most cathartic moment in the app.
///
/// Photosensitivity-safe: one form→shatter pass, no strobing. Gated behind Reduce Motion by
/// the caller (which shows a calm fallback instead).
struct WebBreakView: View {
    let start: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tl in   // 60fps reads identically
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = max(size.width, size.height) * 0.72
                let spokes = 12
                let web = Color(red: 0.86, green: 0.93, blue: 1.0)

                let formP    = min(1, max(0, t / 0.45))           // 0→1: the web draws in
                let shatterP = min(1, max(0, (t - 0.5) / 0.8))    // 0→1: it flies apart (after the crack)
                let alpha = (t < 0.5 ? formP : (1 - shatterP)) * 0.9
                guard alpha > 0.012 else { return }

                let push = (1 + shatterP * 0.9) * formP           // radius grows as it shatters
                func pt(_ i: Double, _ r: Double) -> CGPoint {
                    let a = i / Double(spokes) * 2 * .pi
                    return CGPoint(x: center.x + cos(a) * r * push,
                                   y: center.y + sin(a) * r * push)
                }

                // Spokes (snap into segments during shatter)
                var spokePath = Path()
                for i in 0..<spokes {
                    let outer = pt(Double(i), R)
                    if shatterP > 0.05 {
                        // the spoke breaks: a gap opens near the centre
                        spokePath.move(to: pt(Double(i), R * (0.35 + shatterP * 0.3)))
                        spokePath.addLine(to: outer)
                    } else {
                        spokePath.move(to: center); spokePath.addLine(to: outer)
                    }
                }
                ctx.stroke(spokePath, with: .color(web.opacity(alpha)), lineWidth: 1.7)

                // Concentric threads — drop segments as it snaps
                let rings = 5
                for ring in 1...rings {
                    let r = R * Double(ring) / Double(rings)
                    var ringPath = Path()
                    for i in 0..<spokes {
                        if shatterP > 0, (i + ring) % 3 == Int(shatterP * 4) % 3 { continue }  // snapped gap
                        ringPath.move(to: pt(Double(i), r))
                        ringPath.addLine(to: pt(Double(i + 1), r))
                    }
                    ctx.stroke(ringPath, with: .color(web.opacity(alpha * 0.65)), lineWidth: 1.2)
                }

                // Shards — short streaks bursting outward at the shatter
                if shatterP > 0 {
                    var shards = Path()
                    for i in 0..<28 {
                        let a = Double(i) / 28 * 2 * .pi + shatterP
                        let r0 = R * 0.25 + shatterP * R * 0.85
                        shards.move(to: CGPoint(x: center.x + cos(a) * r0, y: center.y + sin(a) * r0))
                        shards.addLine(to: CGPoint(x: center.x + cos(a) * (r0 + 26), y: center.y + sin(a) * (r0 + 26)))
                    }
                    ctx.stroke(shards, with: .color(web.opacity(alpha)), lineWidth: 2)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
