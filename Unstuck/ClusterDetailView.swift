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
    @State private var lastMovedTitle: String? = nil   // for pull-to-undo after a move
    @State private var punchAt: Date? = nil            // claim screen-punch trigger
    @State private var reelWhy: String? = nil          // big-tier reveal for hard tasks
    @State private var webBreakAt: Date? = nil         // "wall came down" web-shatter trigger
    @State private var topDollar: (amount: Int, jackpot: Bool, multiplier: Int)? = nil   // earned Top Dollar payout
    @State private var showEventPicker = false         // capture → real calendar event
    @State private var eventDate = Date()
    @State private var pendingEventText = ""
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                DetailGraph(items: activeItems, healthNodes: healthNodes, onComplete: complete,
                            onCompleteReminder: completeReminder)
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

                // After a move: a calm, reversible confirmation (RSD-safe, no "done!")
                if let moved = lastMovedTitle {
                    MovedRow(title: moved) { undoMove(moved) }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // How far ahead the time space looks (time cluster only)
                if cluster.zoneType == .timeManagement {
                    horizonControl
                        .padding(.bottom, 6)
                }

                // 🔦 Pick a highlight colour for this cluster (laser palette)
                HighlightRow(cluster: cluster)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 2)

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
                            .font(.system(.callout, design: .monospaced))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
                            // In time/reminders clusters, also push it to the real Reminders.
                            if cluster.zoneType == .reminders || cluster.zoneType == .timeManagement {
                                Button(action: sendToReminders) {
                                    Image(systemName: "bell.badge.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.75).opacity(0.85))
                                }
                                .accessibilityLabel("Also send to Reminders")
                                Button(action: openEventPicker) {
                                    Image(systemName: "calendar.badge.plus")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.75).opacity(0.85))
                                }
                                .accessibilityLabel("Add to calendar")
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
        .overlay { if let t = punchAt { ClaimPunch(start: t).allowsHitTesting(false) } }
        .overlay { if let t = webBreakAt { WebBreakView(start: t).allowsHitTesting(false) } }
        .overlay { if let why = reelWhy { RewardReel(whyLine: why) { withAnimation { reelWhy = nil } } } }
        .overlay(alignment: .bottom) {
            if let td = topDollar {
                TopDollarReveal(amount: td.amount, jackpot: td.jackpot, total: Progression.shared.credits, multiplier: td.multiplier) {
                    let wasJackpot = td.jackpot
                    topDollar = nil
                    // Act 3, only after the payout finishes: the WHY (the deepest hit, alone on stage).
                    if wasJackpot { reelWhy = Self.wallWhys.randomElement() }
                }
                .padding(.bottom, 90)
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showEventPicker) { eventPickerSheet }
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
        // Live sync: an edit made in Google/Apple/Reminders refreshes the open cluster.
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataChanged)) { _ in
            guard cluster.zoneType == .timeManagement else { return }
            Task {
                healthNodes = await CalendarService.shared.fetchUpcoming(forceRefresh: true)
                withAnimation(.easeInOut(duration: 0.3)) { clashes = CalendarService.shared.clashes }
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

    /// Also push the captured text to the real Reminders (cross-platform via EventKit),
    /// while keeping it on the map. User-tapped → a pull, never a demand.
    private func sendToReminders() {
        let trimmed = captureText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        addNode()   // keep it on the map too (this clears captureText)
        Task {
            let ok = await CalendarService.shared.createReminder(title: trimmed)
            HapticEngine.shared.reward(ok ? .success : .soft)   // RSD: no failure buzz — it's still on the map
        }
    }

    /// Tap a reminder node → mark it done in the real Reminders app, then refresh.
    private func completeReminder(_ id: String) {
        HapticEngine.shared.reward(.success)
        Task {
            _ = await CalendarService.shared.completeReminder(id: id)
            healthNodes = await CalendarService.shared.fetchUpcoming(forceRefresh: true)
        }
    }

    private func openEventPicker() {
        let t = captureText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        pendingEventText = t
        eventDate = Date().addingTimeInterval(3600)   // default: an hour from now
        showEventPicker = true
    }

    /// Create a real calendar event at the chosen time, and keep it on the map too.
    private func addEvent() {
        let t = pendingEventText
        showEventPicker = false
        guard !t.isEmpty else { return }
        let item = BrainItem(text: t, cluster: cluster, estimatedMinutes: estimateMinutes)
        modelContext.insert(item)
        captureText = ""; estimateMinutes = nil
        Task {
            let ok = await CalendarService.shared.createEvent(title: t, start: eventDate)
            HapticEngine.shared.reward(ok ? .success : .soft)   // RSD: no failure buzz — it's still on the map
            healthNodes = await CalendarService.shared.fetchUpcoming(forceRefresh: true)
        }
    }

    private var eventPickerSheet: some View {
        VStack(spacing: 18) {
            Text(pendingEventText)
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            DatePicker("", selection: $eventDate)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Color(red: 0.3, green: 0.85, blue: 0.75))
            Button(action: addEvent) {
                Text("add to calendar")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(red: 0.3, green: 0.85, blue: 0.75), in: Capsule())
            }
            Button("not now") { showEventPicker = false }
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(red: 0.04, green: 0.04, blue: 0.10))
    }

    // Adjustable look-ahead for the time space (1–14 days).
    private var horizonControl: some View {
        HStack(spacing: 12) {
            Button { adjustHorizon(-1) } label: {
                Image(systemName: "minus").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6)).frame(width: 26, height: 26).panel(Circle())
            }
            Text("next \(AppSettings.shared.calendarDays) day\(AppSettings.shared.calendarDays == 1 ? "" : "s")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 92)
            Button { adjustHorizon(1) } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6)).frame(width: 26, height: 26).panel(Circle())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar look-ahead")
        .accessibilityValue("\(AppSettings.shared.calendarDays) days")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjustHorizon(1)
            case .decrement: adjustHorizon(-1)
            @unknown default: break
            }
        }
    }

    private func adjustHorizon(_ delta: Int) {
        let n = max(1, min(14, AppSettings.shared.calendarDays + delta))
        guard n != AppSettings.shared.calendarDays else { return }
        AppSettings.shared.calendarDays = n
        HapticEngine.shared.tap()
        Task {
            healthNodes = await CalendarService.shared.fetchUpcoming(forceRefresh: true)
            clashes = CalendarService.shared.clashes
        }
    }

    private func resolveClash(keep: String, drop: String) {
        HapticEngine.shared.reward(.medium)
        CalendarService.shared.resolve(keep: keep, drop: drop)
        Task {
            healthNodes = await CalendarService.shared.fetchUpcoming(forceRefresh: true)
            withAnimation(.easeInOut(duration: 0.3)) {
                clashes = CalendarService.shared.clashes
                lastMovedTitle = CalendarService.shared.isMoved(drop) ? drop : nil
            }
        }
    }

    private func undoMove(_ title: String) {
        HapticEngine.shared.tap()
        CalendarService.shared.undo(title)
        Task {
            healthNodes = await CalendarService.shared.fetchUpcoming(forceRefresh: true)
            withAnimation(.easeInOut(duration: 0.3)) {
                clashes = CalendarService.shared.clashes
                lastMovedTitle = nil
            }
        }
    }

    private func complete(_ item: BrainItem) {
        // Earned signals — what makes this finish a real moment (never random):
        let estimate = item.estimatedMinutes ?? 0
        let wasAvoided = item.state == .fading                                   // you'd been dodging it
        let clearedCluster = cluster.items.filter { $0.state != .done }.count == 1   // this is the last active one
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            item.state = .done
        }
        // Haptic burst is fired by the hold-to-claim itself (DetailNode.claim).
        SpatialAudioService.shared.playBlip(.complete, atX: cluster.positionX, y: cluster.positionY)
        MoodDetector.shared.recordCompletion()
        Progression.shared.recordCompletion()
        NotificationCenter.default.post(name: .taskCompleted, object: nil)

        // Earned credit payout — bigger for harder / avoided / cluster-clearing wins, never a roll.
        let award = Progression.shared.awardCredits(estimatedMinutes: estimate,
                                                    clearedCluster: clearedCluster, wasAvoided: wasAvoided)

        guard !AppSettings.shared.calmMode && !reduceMotion else { return }
        if award.jackpot {
            // A real jackpot is ONE escalating sequence, never a pile-up:
            //   act 1 the break (web shatter + breakthrough) → act 2 the payout (777 meter)
            //   → act 3 the reflection (the WHY reel — chained from the meter's onDone).
            webBreakAt = Date()
            HapticEngine.shared.breakthrough()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { topDollar = award }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { webBreakAt = nil }
        } else {
            punchAt = Date()                          // small "loop closed" pop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { punchAt = nil }
            topDollar = award                          // the BONUS WIN credit meter (with any ×multiplier)
        }
    }

    // Real brain science for finishing a hard/dreaded task — universal, never a label.
    private static let wallWhys = [
        "a dreaded task done clears working-memory load — your brain just got room back.",
        "the hardest part was starting. that resistance you felt is gone now.",
        "finishing what you avoided drops the quiet stress it was costing you.",
        "you proved the wall was climbable. your brain files that for next time.",
        "the dread was bigger than the task. it usually is.",
    ]
}

// MARK: - Full-screen node graph

private struct DetailGraph: View {
    let items: [BrainItem]
    var healthNodes: [HealthSnapshot] = []
    let onComplete: (BrainItem) -> Void
    var onCompleteReminder: (String) -> Void = { _ in }

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
                            .opacity(item.state == .fading ? 0.5 : 1)   // cooled, not called out
                            .position(itemPositions[idx])
                            .transition(.scale(scale: 0.1).combined(with: .opacity))
                    }

                    // Live health nodes — glowing teal, read-only
                    ForEach(Array(healthNodes.enumerated()), id: \.offset) { idx, node in
                        HealthNode(snapshot: node, onComplete: {
                            if let id = node.reminderID { onCompleteReminder(id) }
                        })
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
    @State private var holdProgress: CGFloat = 0
    @State private var claimed = false
    @State private var rampTask: Task<Void, Never>? = nil

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

                // Hold-to-claim charging ring — fills as you hold; release early = no harm
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color(red: 0.30, green: 0.95, blue: 0.70),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(red: 0.30, green: 0.95, blue: 0.70).opacity(Double(holdProgress)), radius: 5)
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
        .onTapGesture {
            if let mins = item.estimatedMinutes {
                HapticEngine.shared.tap()
                FocusSessionController.shared.start(title: item.displayLabel, minutes: Double(mins))
            } else {
                HapticEngine.shared.settle()
            }
        }
        .onLongPressGesture(minimumDuration: 0.8, maximumDistance: 40, pressing: { isPressing in
            pressing = isPressing
            if isPressing { beginRamp() } else if !claimed { cancelRamp() }
        }, perform: claim)
    }

    // MARK: - Hold-to-claim (charge → claim). Honest: only completes a real task.
    private func beginRamp() {
        claimed = false
        HapticEngine.shared.tap()
        withAnimation(.linear(duration: 0.8)) { holdProgress = 1.0 }
        rampTask = Task { @MainActor in
            let steps = 12
            for s in 1...steps {
                try? await Task.sleep(for: .seconds(0.8 / Double(steps)))
                if Task.isCancelled { return }
                if !AppSettings.shared.calmMode { HapticEngine.shared.chargeTick(Double(s) / Double(steps)) }
            }
        }
    }
    private func cancelRamp() {
        rampTask?.cancel(); rampTask = nil
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
    }
    private func claim() {
        claimed = true
        rampTask?.cancel(); rampTask = nil
        if AppSettings.shared.calmMode { HapticEngine.shared.reward(.soft) }
        // Wall tasks: a single sharp release-SNAP — the breakthrough 0.5s later is the
        // explosion. Two max bursts back-to-back blur into mud; escalation needs contrast.
        else if (item.estimatedMinutes ?? 0) >= Progression.wallMinutes { HapticEngine.shared.reward(.rigid) }
        else { HapticEngine.shared.claimBurst() }
        withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
        onComplete()
    }
}

// MARK: - Live health node (read-only, teal glow)

private struct HealthNode: View {
    let snapshot: HealthSnapshot
    var onComplete: () -> Void = {}
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
        .contentShape(Rectangle())
        // Reminder nodes are tappable to mark done; health nodes (steps/sleep) are read-only.
        .onTapGesture { if snapshot.reminderID != nil { onComplete() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(snapshot.reminderID != nil ? .isButton : [])
        .accessibilityHint(snapshot.reminderID != nil ? "Double-tap to mark done" : "")
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

            Text("the other moves to your next free slot — synced across your calendars")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Moved confirmation — calm + reversible (no "done!", RSD-safe)

private struct MovedRow: View {
    let title: String
    let onUndo: () -> Void
    private let green = Color(red: 0.45, green: 0.9, blue: 0.55)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 11))
                .foregroundStyle(green)
            Text("\u{201C}\(title)\u{201D} moved to your next free slot")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text("undo")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .panel(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(RoundedRectangle(cornerRadius: 14, style: .continuous),
               tint: green.opacity(0.07))
    }
}

// MARK: - Highlight picker — customise a cluster's glow (the laser palette)

private struct HighlightRow: View {
    @Bindable var cluster: Cluster
    private let palette = ["4CD9BF", "FFB066", "FF4D94", "5A7DFF", "5CE08C", "B06CFF"]

    var body: some View {
        HStack(spacing: 10) {
            Text("highlight")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            // Off / clear
            Button { set(nil) } label: {
                Image(systemName: "circle.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(cluster.highlightHex == nil ? 0.7 : 0.3))
            }
            .buttonStyle(.plain)
            ForEach(palette, id: \.self) { hex in
                Button { set(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 16, height: 16)
                        .shadow(color: Color(hex: hex).opacity(0.8),
                                radius: cluster.highlightHex == hex ? 5 : 0)
                        .overlay(
                            Circle().stroke(.white.opacity(cluster.highlightHex == hex ? 0.9 : 0),
                                            lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func set(_ hex: String?) {
        HapticEngine.shared.tap()
        withAnimation(.easeInOut(duration: 0.2)) {
            cluster.highlightHex = (cluster.highlightHex == hex) ? nil : hex
        }
    }
}

// MARK: - Claim screen-punch — a quick celebratory pop on completion (RSD-safe, calm-/motion-gated)

private struct ClaimPunch: View {
    let start: Date
    private let tint = Color(red: 0.30, green: 0.95, blue: 0.70)
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            let p = max(0, min(1, t / 0.5))
            let ease = 1 - pow(1 - p, 3)
            ZStack {
                Color.white.opacity((1 - p) * 0.10)                 // brief flash
                Circle()                                            // expanding ring
                    .stroke(tint.opacity((1 - p) * 0.85), lineWidth: 3 * (1 - p) + 0.5)
                    .frame(width: 40 + ease * 280, height: 40 + ease * 280)
                ForEach(0..<10, id: \.self) { i in                  // sparkles fly outward
                    let a = Double(i) / 10 * 2 * .pi
                    Circle().fill(.white.opacity(1 - p))
                        .frame(width: 4, height: 4)
                        .offset(x: cos(a) * (30 + ease * 170), y: sin(a) * (30 + ease * 170))
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
