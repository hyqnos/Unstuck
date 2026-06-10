import SwiftUI
import SwiftData

struct ClusterView: View {
    @Bindable var cluster: Cluster
    let mapSize: CGSize
    var highlighted: Bool = false
    var onTap: (() -> Void)? = nil
    var onMoved: (() -> Void)? = nil

    @GestureState private var dragOffset: CGSize = .zero
    @State private var breathing = false
    @State private var healthNodes: [HealthSnapshot] = []
    @State private var clashCount = 0   // calendar overlaps, for the gentle hint
    @State private var resurface = false   // silent-reminder gentle breathing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Tactile depth on touch (0 = resting, 0.5 = dipped in)
    @State private var pressDepth: CGFloat = 0
    @State private var isDragging = false

    // Fixed per instance — never recalculates, never causes external re-render
    private let breathDuration: Double = Double.random(in: 3.5...5.5)
    private let breathAmplitude: CGFloat = 1.018

    private let width: CGFloat = 160
    private let graphHeight: CGFloat = 110

    private var x: CGFloat { cluster.positionX * mapSize.width + dragOffset.width }
    private var y: CGFloat { cluster.positionY * mapSize.height + dragOffset.height }

    private var activeItems: [BrainItem] {
        cluster.items.filter { $0.state != .done }
    }

    // A "silent reminder": the reminders section stays gently present in awareness
    // (object permanence) — but ONLY when something's actually there, and only as a
    // soft calm glow. Never a red pile, never a count, never "overdue" (RSD-safe).
    private var isSilentReminder: Bool {
        cluster.zoneType == .reminders && !activeItems.isEmpty
    }
    private let silentTint = Color(red: 0.40, green: 0.85, blue: 0.80)   // calm teal, not alarming

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Zone label + gentle overlap hint
            HStack(spacing: 5) {
                Text(cluster.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
                if clashCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.62, blue: 0.25))
                            .frame(width: 4, height: 4)
                        Text("\(clashCount) overlap")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.25).opacity(0.85))
                    }
                    .transition(.opacity)
                }
            }

            // Node graph
            NodeGraph(
                items: Array(activeItems.prefix(7)),
                healthNodes: healthNodes,
                size: CGSize(width: width - 24, height: graphHeight)
            )
            .frame(width: width - 24, height: graphHeight)
        }
        .padding(12)
        .frame(width: width, alignment: .topLeading)
        // Frosted panel — cheap translucent fill, no backdrop sampling
        .panel(RoundedRectangle(cornerRadius: 16, style: .continuous),
               tint: highlighted ? .white.opacity(0.12) : nil,
               highlighted: highlighted)
        // Dashed border for messy zones — drawn on top
        .overlay {
            if !cluster.zoneType.isOrganized {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(highlighted ? 0.6 : 0.18),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        // 🔦 Highlight ring — EVERY cluster shows its chromotherapy colour. The default is a
        // tinted border only (no shadow → RAM/GPU-neutral); a user pick upgrades to the full
        // neon glow. All colours avoid red (RSD-safe).
        .overlay {
            let color = Color(hex: cluster.effectiveHighlightHex)
            if cluster.highlightHex != nil {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(color, lineWidth: 1.5)
                    .shadow(color: color.opacity(0.85), radius: 7)
                    .shadow(color: color.opacity(0.5), radius: 15)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(color.opacity(highlighted ? 0.6 : 0.4), lineWidth: 1.2)
                    .allowsHitTesting(false)
            }
        }
        // 🔕 Silent reminder — a soft calm glow behind the card, gently breathing.
        // Keeps the reminders section present without any guilt signal (RSD-safe).
        .background {
            if isSilentReminder {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(silentTint.opacity(resurface ? 0.16 : 0.06))
                    .blur(radius: 16)
                    .scaleEffect(resurface ? 1.05 : 0.98)
                    .allowsHitTesting(false)
            }
        }
        // VoiceOver: one element per cluster, reads its name + count, opens on activate
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("\(cluster.label), \(activeItems.count) item\(activeItems.count == 1 ? "" : "s")"))
        .accessibilityHint(Text("Opens this space"))

        // Tactile depth — a quick dip on touch, pops back on open
        .scaleEffect((breathing ? breathAmplitude : 1.0) * (1 - pressDepth * 0.06))
        .rotation3DEffect(.degrees(pressDepth * 5),
                          axis: (x: 1, y: 0, z: 0),
                          perspective: 0.5)
        .brightness(pressDepth * 0.06)
        .shadow(color: .white.opacity(pressDepth * 0.2), radius: pressDepth * 14)
        .animation(
            .easeInOut(duration: breathDuration).repeatForever(autoreverses: true),
            value: breathing
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...3)) {
                breathing = true
            }
            if isSilentReminder && !reduceMotion {
                withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                    resurface = true
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: highlighted)
        .position(x: x, y: y)
        // Re-runs once onboarding completes, so Health/Calendar permission prompts
        // never bury the first-run intro. Until then, the cards stay quiet.
        .task(id: AppSettings.shared.hasOnboarded) {
            guard AppSettings.shared.hasOnboarded else { return }
            switch cluster.zoneType {
            case .health:
                healthNodes = await HealthService.shared.fetchSnapshot()
            case .timeManagement:
                healthNodes = await CalendarService.shared.fetchUpcoming()
                withAnimation(.easeInOut(duration: 0.4)) {
                    clashCount = CalendarService.shared.clashes.count
                }
            default: break
            }
        }
        // Live sync: external calendar/reminder edits refresh the on-map card too.
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataChanged)) { _ in
            guard AppSettings.shared.hasOnboarded, cluster.zoneType == .timeManagement else { return }
            Task {
                healthNodes = await CalendarService.shared.fetchUpcoming(forceRefresh: true)
                withAnimation(.easeInOut(duration: 0.4)) { clashCount = CalendarService.shared.clashes.count }
            }
        }
        // One gesture: quick TAP opens instantly (with a dip+pop), DRAG past a
        // threshold moves the cluster. No forced hold — opening is the common act.
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragOffset) { v, state, _ in
                    // Only reflect movement once it's clearly a drag (no tap jiggle)
                    state = hypot(v.translation.width, v.translation.height) > 10 ? v.translation : .zero
                }
                .onChanged { v in
                    let d = hypot(v.translation.width, v.translation.height)
                    if d > 10 {
                        if !isDragging { isDragging = true }
                        if pressDepth != 0 {
                            withAnimation(.easeOut(duration: 0.12)) { pressDepth = 0 }
                        }
                    } else if pressDepth == 0 && !isDragging {
                        // Touch down — dip in slightly + soft tick
                        withAnimation(.easeOut(duration: 0.13)) { pressDepth = 0.5 }
                        HapticEngine.shared.tap()
                    }
                }
                .onEnded { v in
                    let d = hypot(v.translation.width, v.translation.height)
                    if isDragging || d > 10 {
                        cluster.positionX = (cluster.positionX * mapSize.width + v.translation.width)
                            .clamped(to: 0...mapSize.width) / mapSize.width
                        cluster.positionY = (cluster.positionY * mapSize.height + v.translation.height)
                            .clamped(to: 0...mapSize.height) / mapSize.height
                        withAnimation(.easeOut(duration: 0.15)) { pressDepth = 0 }
                        onMoved?()
                    } else {
                        // Tap → pop + open immediately
                        HapticEngine.shared.reward(.rigid)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pressDepth = 0 }
                        onTap?()
                    }
                    isDragging = false
                }
        )
    }
}

// MARK: - Node graph (mini constellation)

struct NodeGraph: View {   // internal (was private) so rng is unit-testable
    let items: [BrainItem]
    var healthNodes: [HealthSnapshot] = []
    let size: CGSize

    private var totalCount: Int { items.count + healthNodes.count }
    private var isEmpty: Bool { totalCount == 0 }

    var body: some View {
        if isEmpty {
            Text("empty")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            let itemPositions   = positions(count: items.count, offset: 0)
            let healthPositions = positions(count: healthNodes.count, offset: items.count)
            let allPositions    = itemPositions + healthPositions

            ZStack {
                // Constellation lines — a RELATIVE NEIGHBOURHOOD GRAPH: keep edge i–j only
                // if no third node sits in their "lune" (closer to both than they are to
                // each other). It always contains the spanning tree (so it stays connected)
                // but adds the locally-meaningful edges → a fuller, still crossing-free shape.
                Canvas { ctx, _ in
                    for (i, j) in Self.rng(allPositions) {
                        var path = Path()
                        path.move(to: allPositions[i])
                        path.addLine(to: allPositions[j])
                        ctx.stroke(path, with: .color(.white.opacity(0.16)),
                                   style: StrokeStyle(lineWidth: 0.8))
                    }
                }

                // User item nodes — fading (cooled) ones render dimmer, never red
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    NodeView(label: item.displayLabel)
                        .opacity(item.state == .fading ? 0.45 : 1)
                        .position(itemPositions[idx])
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }

                // Health nodes — teal
                ForEach(Array(healthNodes.enumerated()), id: \.offset) { idx, node in
                    MiniHealthNode(snapshot: node)
                        .position(healthPositions[idx])
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
        }
    }

    private func positions(count: Int, offset: Int) -> [CGPoint] {
        let padding: CGFloat = 14
        let cx = size.width / 2
        let cy = size.height / 2
        let maxR = Swift.min(size.width, size.height) * 0.36

        return (0..<count).map { i in
            let idx = i + offset
            guard idx > 0 else { return CGPoint(x: cx, y: cy) }
            // Vogel's sunflower model — golden-angle spiral with a √-radius so the nodes
            // spread with EVEN area density (no empty centre, no crowded rim).
            let angle = Double(idx) * 2.399963            // golden angle, in radians
            let r = maxR * sqrt(CGFloat(idx) / CGFloat(Swift.max(1, totalCount - 1)))
            return CGPoint(
                x: (cx + CGFloat(cos(angle)) * r).clamped(to: padding...(size.width - padding)),
                y: (cy + CGFloat(sin(angle)) * r).clamped(to: padding...(size.height - padding))
            )
        }
    }

    /// Relative neighbourhood graph (O(n³), fine for a handful of nodes). Edge i–j is
    /// kept iff no other node k is closer to BOTH endpoints than they are to each other
    /// — i.e. the lune between them is empty. Always contains the minimum spanning tree,
    /// so the constellation stays connected, but it's richer and crossing-free.
    static func rng(_ pts: [CGPoint]) -> [(Int, Int)] {
        guard pts.count > 1 else { return [] }
        func d2(_ a: Int, _ b: Int) -> CGFloat {
            let dx = pts[a].x - pts[b].x, dy = pts[a].y - pts[b].y
            return dx * dx + dy * dy
        }
        var edges: [(Int, Int)] = []
        for i in pts.indices {
            for j in (i + 1)..<pts.count {
                let dij = d2(i, j)
                var keep = true
                for k in pts.indices where k != i && k != j {
                    if Swift.max(d2(i, k), d2(j, k)) < dij { keep = false; break }
                }
                if keep { edges.append((i, j)) }
            }
        }
        return edges
    }
}

// MARK: - Single graph node

private struct NodeView: View {
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(.white.opacity(0.7))
                .frame(width: 5, height: 5)

            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Mini health node for map card

private struct MiniHealthNode: View {
    let snapshot: HealthSnapshot
    @State private var pulse = false

    private var color: Color { snapshot.tint ?? Color(red: 0.3, green: 0.85, blue: 0.75) }

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(color.opacity(pulse ? 0.9 : 0.55))
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: pulse ? 4 : 2)
            Text(snapshot.label)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(color.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8)
                .repeatForever(autoreverses: true)
                .delay(Double.random(in: 0...1.5))) {
                pulse = true
            }
        }
    }
}

// MARK: - Helpers

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
