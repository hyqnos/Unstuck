import SwiftUI

/// A compact widget-style pager pinned on the map. Flip through clusters with ‹ › —
/// the card previews each one (name, count, node dots, its highlight tint) AND the
/// map flies to center that cluster as you land on it. Tap the card to open it.
///
/// A calm, linear remote-control for the spatial map — for moods where the full
/// map is too much. Styled like the home-screen widget. Never demands anything;
/// it just lets you step through (PDA-safe).
struct ClusterPager: View {
    let clusters: [Cluster]                 // stable-ordered by the caller
    @Binding var index: Int
    var onFly: (Cluster) -> Void            // pan the map to center this cluster
    var onOpen: (Cluster) -> Void           // open its detail

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

            HStack(spacing: 8) {
                stepButton("chevron.left", "Previous cluster") { move(-1) }

                Button { onOpen(c) } label: {
                    VStack(spacing: 5) {
                        HStack(spacing: 6) {
                            Text(c.label)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                            Text("\(active.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(col)
                        }
                        HStack(spacing: 4) {
                            ForEach(active.prefix(6), id: \.id) { _ in
                                Circle().fill(col.opacity(0.8)).frame(width: 4, height: 4)
                            }
                            if active.isEmpty {
                                Text("empty").font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(c.label), \(active.count) item\(active.count == 1 ? "" : "s")")

                stepButton("chevron.right", "Next cluster") { move(1) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(width: 232)
            .panel(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: col.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(col.opacity(0.4), lineWidth: 1))
            .shadow(color: col.opacity(0.25), radius: 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
        }
    }

    private func stepButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 30, height: 30)
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
