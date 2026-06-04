import SwiftUI

/// A widget-style cluster carousel pinned on the map. Flip through clusters with the
/// ‹ › arrows **or by swiping the card left/right** — the card previews each one (name,
/// count, node dots, its highlight tint), paging dots underneath show where you are, AND
/// the map flies to center that cluster as you land on it. Tap the card to open it.
///
/// A calm, tactile remote-control for the spatial map — for moods where the full map is
/// too much. Styled like the home-screen widget. Never demands anything; it just lets
/// you step through (PDA-safe).
struct ClusterPager: View {
    let clusters: [Cluster]                 // stable-ordered by the caller
    @Binding var index: Int
    var onFly: (Cluster) -> Void            // pan the map to center this cluster
    var onOpen: (Cluster) -> Void           // open its detail

    @State private var dragX: CGFloat = 0

    private func tint(_ c: Cluster) -> Color {
        if let hex = c.highlightHex { return Color(hex: hex) }
        return c.zoneType.isOrganized
            ? Color(red: 0.30, green: 0.85, blue: 0.75)
            : Color(red: 0.60, green: 0.66, blue: 0.78)
    }

    var body: some View {
        if !clusters.isEmpty {
            let n = clusters.count
            let i = ((index % n) + n) % n
            let c = clusters[i]
            let active = c.items.filter { $0.state != .done }
            let col = tint(c)

            VStack(spacing: 9) {
                HStack(spacing: 10) {
                    stepButton("chevron.left", "Previous cluster") { move(-1) }
                    card(c, active, col)
                    stepButton("chevron.right", "Next cluster") { move(1) }
                }
                pagingDots(n: n, current: i, col: col)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(width: 286)
            .panel(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: col.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(col.opacity(0.45), lineWidth: 1.2))
            .shadow(color: col.opacity(0.30), radius: 9)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
        }
    }

    // The previewing card — tap to open, swipe left/right to page.
    private func card(_ c: Cluster, _ active: [BrainItem], _ col: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Text(c.label)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95)).lineLimit(1)
                Text("\(active.count)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(col)
            }
            HStack(spacing: 5) {
                ForEach(active.prefix(7), id: \.id) { _ in
                    Circle().fill(col.opacity(0.85)).frame(width: 5, height: 5)
                }
                if active.isEmpty {
                    Text("empty").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .offset(x: dragX)
        .onTapGesture { onOpen(c) }
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in dragX = max(-44, min(44, v.translation.width)) }
                .onEnded { v in
                    let t = v.translation.width
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragX = 0 }
                    if t <= -30 { move(1) }          // swipe left → next
                    else if t >= 30 { move(-1) }     // swipe right → previous
                }
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Open \(c.label), \(active.count) item\(active.count == 1 ? "" : "s")")
        .accessibilityHint("Swipe, or use the arrows, to change cluster")
    }

    // Where-am-I dots; the active one stretches into a capsule. Falls back to "i / n" when crowded.
    @ViewBuilder
    private func pagingDots(n: Int, current: Int, col: Color) -> some View {
        if n <= 10 {
            HStack(spacing: 5) {
                ForEach(0..<n, id: \.self) { k in
                    Capsule()
                        .fill(k == current ? col : Color.white.opacity(0.22))
                        .frame(width: k == current ? 15 : 5, height: 5)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
        } else {
            Text("\(current + 1) / \(n)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func stepButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 34, height: 34)
                .panel(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func move(_ d: Int) {
        guard !clusters.isEmpty else { return }
        HapticEngine.shared.tap()
        let n = clusters.count
        let next = (((index + d) % n) + n) % n
        index = next
        onFly(clusters[next])
    }
}
