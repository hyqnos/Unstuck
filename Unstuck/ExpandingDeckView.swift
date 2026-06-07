import SwiftUI

/// A card-deck browse mode — an "expanding collection" fidget. A calm, one-handed
/// way to flip through clusters: tap a card and it expands (matchedGeometry) into
/// a larger card showing what's inside; "open" dives into the full detail.
///
/// Native SwiftUI, zero dependencies. Suits lower-energy moods, where the spatial
/// map can feel like too much — a quieter, linear way in. The map stays home.
struct ExpandingDeckView: View {
    let clusters: [Cluster]
    var onOpenDetail: (Cluster) -> Void
    var onClose: () -> Void

    @Namespace private var ns
    @State private var expandedID: UUID? = nil

    private func tint(_ c: Cluster) -> Color { Color(hex: c.effectiveHighlightHex) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.04, blue: 0.10),
                                    Color(red: 0.01, green: 0.01, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .onTapGesture { expandedID == nil ? onClose() : collapse() }

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(clusters, id: \.id) { c in
                        if expandedID == c.id {
                            Color.clear.frame(height: 92)            // hold the slot while expanded
                        } else {
                            collapsedCard(c)
                                .matchedGeometryEffect(id: c.id, in: ns)
                                .onTapGesture { expand(c) }
                        }
                    }
                }
                .padding(20)
                .padding(.top, 56)
            }

            // Header
            VStack {
                HStack {
                    Text("cards")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 34, height: 34)
                            .panel(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                Spacer()
            }

            // Expanded card (on top, matched from its collapsed slot)
            if let id = expandedID, let c = clusters.first(where: { $0.id == id }) {
                expandedCard(c)
                    .matchedGeometryEffect(id: c.id, in: ns)
                    .padding(20)
                    .zIndex(2)
            }
        }
    }

    // MARK: - Cards

    private func collapsedCard(_ c: Cluster) -> some View {
        let active = c.items.filter { $0.state != .done }
        let col = tint(c)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(c.label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text("\(active.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(col)
            }
            HStack(spacing: 5) {
                ForEach(active.prefix(9), id: \.id) { _ in
                    Circle().fill(col.opacity(0.8)).frame(width: 5, height: 5)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 92)
        .panel(RoundedRectangle(cornerRadius: 18, style: .continuous), tint: col.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(col.opacity(0.45), lineWidth: 1))
        .shadow(color: col.opacity(0.3), radius: 6)
    }

    private func expandedCard(_ c: Cluster) -> some View {
        let active = c.items.filter { $0.state != .done }
        let col = tint(c)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(c.label)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Button { collapse() } label: {
                    Image(systemName: "chevron.down").foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if active.isEmpty {
                        Text("nothing here yet")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    ForEach(active.prefix(14), id: \.id) { item in
                        HStack(spacing: 8) {
                            Circle().fill(col).frame(width: 6, height: 6)
                            Text(item.displayLabel)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                }
            }
            Button { onOpenDetail(c) } label: {
                Text("open")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.02, green: 0.10, blue: 0.08))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(col))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: 460, alignment: .topLeading)
        .panel(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: col.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(col.opacity(0.7), lineWidth: 1.5))
        .shadow(color: col.opacity(0.4), radius: 16)
    }

    // MARK: - Transitions

    private func expand(_ c: Cluster) {
        HapticEngine.shared.tap()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { expandedID = c.id }
    }
    private func collapse() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { expandedID = nil }
    }
}
