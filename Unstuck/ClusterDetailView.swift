import SwiftUI
import SwiftData

struct ClusterDetailView: View {
    @Bindable var cluster: Cluster
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var captureText = ""
    @State private var estimateMinutes: Int? = nil
    @State private var healthNodes: [HealthSnapshot] = []
    @State private var clashes: [ClashSuggestion] = []
    @FocusState private var focused: Bool

    private var activeItems: [BrainItem] {
        cluster.items.filter { $0.state != .done }
    }

    var body: some View {
        ZStack {
            // Near-opaque deep-space backdrop (no material blur — cheap)
            Color(red: 0.03, green: 0.03, blue: 0.09).opacity(0.97).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cluster.label)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("\(activeItems.count) node\(activeItems.count == 1 ? "" : "s")")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                    Button(action: {
                        HapticEngine.shared.tap()
                        onClose()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Graph
                DetailGraph(items: activeItems, healthNodes: healthNodes, onComplete: complete)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Overlap suggestions — gentle, pattern-based, never a command
                if !clashes.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(clashes) { c in
                            ClashRow(clash: c) { keep, drop in resolveClash(keep: keep, drop: drop) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                // Capture area
                VStack(spacing: 8) {
                    // Time estimate chips
                    HStack(spacing: 8) {
                        Text("how long?")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                        ForEach([2, 5, 15, 30], id: \.self) { mins in
                            Button {
                                HapticEngine.shared.tap()
                                estimateMinutes = estimateMinutes == mins ? nil : mins
                            } label: {
                                Text("\(mins)m")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(estimateMinutes == mins ? 1.0 : 0.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .panel(Capsule(),
                                           tint: estimateMinutes == mins ? .white.opacity(0.85) : nil,
                                           highlighted: estimateMinutes == mins)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        TextField("add a node...", text: $captureText)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .focused($focused)
                            .onSubmit(addNode)

                        if !captureText.isEmpty {
                            Button(action: addNode) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .panel(RoundedRectangle(cornerRadius: 16, style: .continuous), highlighted: focused)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onTapGesture { focused = false }
        .task {
            switch cluster.zoneType {
            case .health:
                healthNodes = await HealthService.shared.fetchSnapshot()
            case .timeManagement:
                healthNodes = await CalendarService.shared.fetchUpcoming()
                clashes = CalendarService.shared.clashes
            default: break
            }
        }
    }

    private func addNode() {
        let trimmed = captureText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let item = BrainItem(text: trimmed, cluster: cluster, estimatedMinutes: estimateMinutes)
        modelContext.insert(item)
        captureText = ""
        estimateMinutes = nil
        HapticEngine.shared.reward(.light)
    }

    private func resolveClash(keep: String, drop: String) {
        HapticEngine.shared.reward(.medium)
        CalendarService.shared.resolve(keep: keep, drop: drop)
        Task {
            healthNodes = await CalendarService.shared.fetchUpcoming(forceRefresh: true)
            withAnimation(.easeInOut(duration: 0.3)) {
                clashes = CalendarService.shared.clashes
            }
        }
    }

    private func complete(_ item: BrainItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            item.state = .done
        }
        HapticEngine.shared.complete()
        SpatialAudioService.shared.playBlip(.complete, atX: cluster.positionX, y: cluster.positionY)
        MoodDetector.shared.recordCompletion()
        Progression.shared.recordCompletion()
        NotificationCenter.default.post(name: .taskCompleted, object: nil)
    }
}

// MARK: - Full-screen node graph

private struct DetailGraph: View {
    let items: [BrainItem]
    var healthNodes: [HealthSnapshot] = []
    let onComplete: (BrainItem) -> Void

    private var totalCount: Int { items.count + healthNodes.count }

    var body: some View {
        if totalCount == 0 {
            VStack(spacing: 12) {
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: 1)
                    .frame(width: 60, height: 60)
                Text("no nodes yet")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let itemPositions   = nodePositions(count: items.count, offset: 0, in: geo.size)
                let healthPositions = nodePositions(count: healthNodes.count, offset: items.count, in: geo.size)
                let allPositions    = itemPositions + healthPositions

                ZStack {
                    // Connection lines
                    Canvas { ctx, _ in
                        for i in 0..<allPositions.count {
                            for j in (i + 1)..<allPositions.count {
                                let threshold = (geo.size.width + geo.size.height) * 0.25
                                let dx = allPositions[i].x - allPositions[j].x
                                let dy = allPositions[i].y - allPositions[j].y
                                let dist = sqrt(dx * dx + dy * dy)
                                guard dist < threshold else { continue }
                                let alpha = Double(1 - dist / threshold) * 0.3
                                var path = Path()
                                path.move(to: allPositions[i])
                                path.addLine(to: allPositions[j])
                                ctx.stroke(path, with: .color(.white.opacity(alpha)),
                                           style: StrokeStyle(lineWidth: 0.8))
                            }
                        }
                    }

                    // User-created nodes
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        DetailNode(item: item, onComplete: { onComplete(item) })
                            .position(itemPositions[idx])
                            .transition(.scale(scale: 0.1).combined(with: .opacity))
                    }

                    // Live health nodes — glowing teal, read-only
                    ForEach(Array(healthNodes.enumerated()), id: \.offset) { idx, node in
                        HealthNode(snapshot: node)
                            .position(healthPositions[idx])
                            .transition(.scale(scale: 0.1).combined(with: .opacity))
                    }
                }
            }
        }
    }

    private func nodePositions(count: Int, offset: Int, in size: CGSize) -> [CGPoint] {
        let cx = size.width / 2
        let cy = size.height / 2
        let maxR = Swift.min(size.width, size.height) * 0.38
        let padding: CGFloat = 44

        return (0..<count).map { i in
            let idx = i + offset
            guard idx > 0 else { return CGPoint(x: cx, y: cy) }
            let angle = Double(idx) * 2.399963
            let r = maxR * (0.45 + 0.55 * CGFloat(idx) / CGFloat(Swift.max(1, totalCount)))
            return CGPoint(
                x: (cx + CGFloat(cos(angle)) * r).clamped(to: padding...(size.width - padding)),
                y: (cy + CGFloat(sin(angle)) * r).clamped(to: padding...(size.height - padding))
            )
        }
    }
}

// MARK: - Detail node (tappable to complete)

private struct DetailNode: View {
    let item: BrainItem
    let onComplete: () -> Void

    @State private var pressing = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Outer ring — shows time estimate as an arc / full ring
                if let mins = item.estimatedMinutes {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    Text(mins < 60 ? "\(mins)m" : "\(mins/60)h")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(y: 14)
                }

                Circle()
                    .fill(pressing ? .white.opacity(0.4) : .white.opacity(0.85))
                    .frame(width: 10, height: 10)
                    .shadow(color: .white.opacity(0.35), radius: pressing ? 8 : 3)
                    .scaleEffect(pressing ? 1.4 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressing)
            }

            VStack(spacing: 2) {
                // The AI-named main idea
                Text(item.displayLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .frame(maxWidth: 100)

                // The original raw input — the sub-detail, shown only if it differs
                if item.title != nil, item.text != item.displayLabel {
                    Text(item.text)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                        .frame(maxWidth: 100)
                }
            }
        }
        .contentShape(Circle().size(CGSize(width: 60, height: 60)).offset(x: -25, y: -25))
        .onLongPressGesture(minimumDuration: 0.4, pressing: { isPressing in
            pressing = isPressing
            if isPressing { HapticEngine.shared.tap() }
        }, perform: onComplete)
    }
}

// MARK: - Live health node (read-only, teal glow)

private struct HealthNode: View {
    let snapshot: HealthSnapshot
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Urgency ring — fills based on how "alert" the metric is
                Circle()
                    .stroke(tealColor.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                Circle()
                    .trim(from: 0, to: snapshot.urgency)
                    .stroke(tealColor.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))

                Image(systemName: snapshot.icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tealColor)
                    .scaleEffect(pulse ? 1.15 : 1.0)
            }

            Text(snapshot.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(tealColor.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var tealColor: Color {
        snapshot.tint ?? Color(red: 0.3, green: 0.85, blue: 0.75)
    }
}

// MARK: - Clash row — declarative lean + two gentle choices (never a command)

private struct ClashRow: View {
    let clash: ClashSuggestion
    let onChoose: (_ keep: String, _ drop: String) -> Void

    private let amber = Color(red: 1.0, green: 0.62, blue: 0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(amber).frame(width: 5, height: 5)
                Text("\(clash.time) — two things overlap")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            // The lean, framed as a pattern — not an order
            Text("you'd usually keep \u{201C}\(clash.keep)\u{201D} — \(clash.reason)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(amber.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            // The user decides; the app just learns
            HStack(spacing: 10) {
                choice(clash.keep) { onChoose(clash.keep, clash.drop) }
                choice(clash.drop) { onChoose(clash.drop, clash.keep) }
            }

            Text("the other slides to your next free slot")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(RoundedRectangle(cornerRadius: 14, style: .continuous),
               tint: amber.opacity(0.06))
    }

    private func choice(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("keep \(title)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .panel(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
