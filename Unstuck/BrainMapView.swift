import SwiftUI
import SwiftData
import WidgetKit

struct BrainMapView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    @Query var clusters: [Cluster]
    @Query(sort: \CoachingNote.timesShown) var coachingNotes: [CoachingNote]

    // Capture flow + its transient animation state lives here
    @State var capturer = CaptureController()

    // Canvas pan + zoom + rotation
    @State var panOffset: CGSize = .zero
    @State var userScale: CGFloat = 1.0
    @State var mapRotation: Angle = .zero
    @GestureState var gestureRotation: Angle = .zero   // feeds the tilt layer

    // Overlays
    @State var focusedCluster: Cluster? = nil
    @State var showingVoiceCapture = false
    @State var mapSize: CGSize = .zero         // cached for collision-avoidance
    @State var overviewMode = false            // four-finger constellation overview
    @State var showDeck = false                // expanding card-deck browse fidget
    @State var showDump = false                // brain-dump valve (swipe up on the capture bar)
    @State var showAchievements = false        // "look what you did" — credits + milestones
    @State var pagerIndex = 0                   // on-map cluster pager position
    @State var chromeRests = false             // idle → controls fade to a whisper (deference)
    @State private var chromeRestTask: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var showIntro = false               // launch laser show
    @State var introStart = Date()
    @State var celebrateStart: Date? = nil     // per-completion rave (insane mode)
    @State var youTaps = 0                     // 🥚 secret stage taps
    @State var secretMessage: String? = nil
    @State var webStart: Date? = nil           // 🥚 spider-web thwip
    @State var showOnboarding = !AppSettings.shared.hasOnboarded
    var voice = VoiceCapture()
    let motion = MotionAdaptor.shared
    let mood   = MoodDetector.shared

    let patterns   = PatternService.shared
    let returnState = ReturnState.shared
    let progression = Progression.shared
    let settings   = AppSettings.shared

    // Phase 6 — paralysis support
    @State var showingBreadcrumbs = false
    @State var survivalItem: BrainItem? = nil   // the one glowing thing
    @State var showingTeach = false
    @State var teachText = ""

    private var theme: MoodTheme { MoodTheme.theme(for: mood.mode) }

    // A tiny, climbable win — shortest not-done item, prefers ones with a time estimate.
    // Fading (cooled) items are INCLUDED: an old 2-minute thing is the perfect gentle crumb,
    // and finishing one pays the ×2 came-back-for-it bonus.
    var easyWin: BrainItem? {
        let active = clusters.flatMap { $0.items }.filter { $0.state != .done }
        return active.sorted { a, b in
            let am = a.estimatedMinutes ?? 999
            let bm = b.estimatedMinutes ?? 999
            if am != bm { return am < bm }
            return a.text.count < b.text.count
        }.first
    }

    // True until the very first thought lands — drives the cold-open hint
    var isMapEmpty: Bool {
        clusters.allSatisfy { $0.items.isEmpty }
    }

    // Sensory-dial button appearance
    var sensoryIcon: String {
        switch settings.sensory {
        case .calm:   return "moon.fill"
        case .normal: return "moon"
        case .insane: return "flame.fill"
        }
    }
    var sensoryTint: Color {
        switch settings.sensory {
        case .calm:   return .white
        case .normal: return .white.opacity(0.55)
        case .insane: return Color(red: 1.0, green: 0.35, blue: 0.2)
        }
    }

    // The user's own recent words
    var ownWords: [BrainItem] {
        clusters.flatMap { $0.items }
            .filter { $0.state != .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // Whether it's a "good day" — when teach-the-app gently offers itself
    var isGoodDay: Bool {
        mood.mode == .ready || mood.mode == .hyperfocus
    }

    // Most urgent cluster for overwhelm mode
    var mostUrgentCluster: Cluster? {
        clusters.max(by: { a, b in
            let aUrgency = a.items.filter { $0.state == .active }.map(\.urgency).max() ?? 0
            let bUrgency = b.items.filter { $0.state == .active }.map(\.urgency).max() ?? 0
            return aUrgency < bUrgency
        })
    }

    // Manual rotation only — gyro tilt is handled inside TiltLayer (isolated 60Hz view)
    var manualRotation: Angle { mapRotation + gestureRotation }


    private var mapCanvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // Background — always full screen, never moves
                StarfieldView()
                    .opacity(theme.starOpacity)
                    .animation(.easeInOut(duration: 2.0), value: theme.starOpacity)

                // ── CANVAS LAYER (pan + zoom + 3D tilt) ──────────
                // Frosted panels (no Liquid Glass) — nothing here samples the
                // backdrop, so 3D-transforming it is cheap.
                TiltLayer(manualRotation: manualRotation) {
                ZStack {
                    // Background hit area — pan + three-finger spread
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(count: 1) { } // prevent fall-through
                        .simultaneousGesture(
                            SpatialTapGesture(count: 1)
                                .onEnded { _ in }
                        )
                        .onAppear {
                            mapSize = geo.size
                            relaxClusters(in: geo.size)   // un-pile on launch
                        }

                    // YOU + collection ring (progress toward the next milestone — the almost-full pull)
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.08), lineWidth: 2)
                            .frame(width: 54, height: 54)
                        Circle()
                            .trim(from: 0, to: progression.progressToNext)
                            .stroke(Color(red: 0.3, green: 0.85, blue: 0.75).opacity(0.6),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 54, height: 54)
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progression.progressToNext)
                        Text("YOU")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(theme.youOpacity))
                    }
                    .contentShape(Circle())
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .animation(.easeInOut(duration: 2.0), value: theme.youOpacity)
                    // 🥚 the stage is secretly a DJ booth
                    .onTapGesture { tapYou() }
                    .onLongPressGesture(minimumDuration: 0.5) { dropTheBeat() }

                    ForEach(clusters) { cluster in
                        let isPriority = cluster.id == mostUrgentCluster?.id
                        let opacity = mood.mode == .overwhelm
                            ? (isPriority ? theme.priorityClusterOpacity : theme.clusterOpacity)
                            : theme.clusterOpacity

                        ClusterView(
                            cluster: cluster,
                            mapSize: geo.size,
                            highlighted: cluster.id == capturer.highlightID,
                            onTap: {
                                mood.recordTap()
                                SpatialAudioService.shared.playBlip(.open, atX: cluster.positionX, y: cluster.positionY)
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                    focusedCluster = cluster
                                }
                            },
                            onMoved: {
                                // Keep the dragged one put, nudge any it landed on
                                resolveOverlaps(around: cluster, in: geo.size)
                            }
                        )
                        .opacity(opacity)
                        .animation(.easeInOut(duration: 1.5), value: opacity)
                    }

                    // Knowledge crumbs — scattered on canvas, found not pushed
                    ForEach(patterns.crumbs) { crumb in
                        CrumbView(crumb: crumb)
                            .position(
                                x: crumb.positionX * geo.size.width,
                                y: crumb.positionY * geo.size.height
                            )
                            .opacity(mood.mode == .overwhelm ? 0 : 0.9)
                            .animation(.easeInOut(duration: 1.5), value: mood.mode)
                    }

                    // Overwhelm / hyperfocus nudge
                    if let nudge = theme.nudge {
                        Text(nudge)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .panel(Capsule())
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.08)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                } // end TiltLayer content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Two-finger rotate stays here — its live value feeds the tilt layer
                .gesture(
                    RotationGesture()
                        .updating($gestureRotation) { v, state, _ in state = v }
                        .onEnded { [self] v in
                            var result = mapRotation + v
                            // Snap back to level when within ~12° — the map wants to be upright
                            if abs(result.degrees) < 12 {
                                result = .zero
                                HapticEngine.shared.tap()
                            }
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                mapRotation = result
                            }
                        }
                )
                // Pan + pinch + double-tap (with rubber-band + inertia)
                .mapCanvasGestures(panOffset: $panOffset, userScale: $userScale,
                                   mapRotation: $mapRotation, size: geo.size)
                // Focus-dive zoom animation (capture) — outermost, as before
                .scaleEffect(capturer.diveScale, anchor: capturer.diveAnchor)
                .animation(.spring(response: 0.38, dampingFraction: 0.68), value: capturer.dropPhase)

                // ── CAPTURE BAR (never moves) ─────────────────────
                VStack(spacing: 10) {
                    // First-run hint — only while the map is completely empty
                    if isMapEmpty {
                        Text("anything on your mind — type it, or hold the action button")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                            .transition(.opacity)
                    }
                    QuickCaptureBar { text in
                        mood.recordTap()
                        checkSecretWord(text)   // 🥚 magic words
                        Task { await capturer.capture(text: text, clusters: clusters, context: modelContext) }
                    }
                    // Swipe up on the bar → the brain-dump valve (empty your head all at once).
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 28)
                            .onEnded { v in
                                if v.translation.height < -45 && abs(v.translation.width) < 70 {
                                    HapticEngine.shared.tap()
                                    withAnimation(.easeOut(duration: 0.25)) { showDump = true }
                                }
                            }
                    )
                }
                .opacity(theme.captureBarOpacity)
                .animation(.easeInOut(duration: 2.0), value: theme.captureBarOpacity)
            }
            // Northern-lights mood indicator — sky-glow at the top, above the glass
            .overlay(alignment: .top) {
                AuroraView(colors: theme.auroraColors, intensity: theme.auroraIntensity)
            }
            // Four-finger tap — constellation overview (trackpad overview gesture)
            .background(MultiFingerTap(touches: 4) { toggleOverview() })
        }
    }

    var body: some View {
        mapCanvas
        .ignoresSafeArea()
        .onAppear {
            seedIfNeeded()
            fadeStaleItems()   // the RSD promise: untouched items cool, never accumulate
            scheduleChromeRest()
            motion.start()
            mood.start()

            // Phase 6 — silently check if returning from a freeze
            returnState.recordOpen()
            if returnState.returningFromFreeze && !ownWords.isEmpty {
                showingBreadcrumbs = true
            }

            // Cold-start: let the map paint on the FIRST frame, then bloom the heavier
            // work a beat later. Firing the pattern pass, the audio-engine spin-up and
            // the laser-show Canvas all on frame one — on top of the starfield, aurora,
            // clusters and tilt layer — is what made a cold launch hitch. Deferring also
            // reads nicer: the calm map appears instantly, then the energy blooms in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                patterns.analyse(clusters: clusters)
                syncWidget()        // seed the Home-Screen cluster widget

                // Spatial audio only when NOT in breadcrumb mode (keep return calm + quiet).
                if !showingBreadcrumbs {
                    SpatialAudioService.shared.start(clusters: clusters)
                }

                // Welcome rave — brief, non-blocking, skipped in calm mode, during a
                // freeze-return, and on the very first run (meet the calm map first).
                if !settings.calmMode && !showingBreadcrumbs && !showOnboarding && !reduceMotion {
                    introStart = Date()
                    showIntro = true
                    HapticEngine.shared.reward(.rigid)
                    let introLen = settings.insaneMode ? 4.0 : 2.6
                    DispatchQueue.main.asyncAfter(deadline: .now() + introLen) { showIntro = false }
                }
            }
        }
        // Real wins (a completion, or a brain-dump landing) — refresh the widget, and in
        // insane mode pop a quick laser burst
        .onReceive(NotificationCenter.default.publisher(for: .taskCompleted)) { _ in onRealWin() }
        .onReceive(NotificationCenter.default.publisher(for: .brainDumped)) { _ in onRealWin() }
        // App icon reflects the mood you leave in (changed on background to avoid
        // interrupting mid-session with iOS's icon-change alert)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                AppIconManager.update(for: mood.mode)
            }
            syncWidget()        // keep the Home-Screen cluster widget current
        }
        // Focus music re-tunes itself live as the brain mode shifts; the Dynamic Island
        // focus pill recolors to match (a no-op when no session is running).
        .onChange(of: mood.mode) { _, newMode in
            if settings.focusMusic {
                SpatialAudioService.shared.setMood(newMode)
            }
            FocusSessionController.shared.refreshVisuals()
        }
        // Keep the focus pill's music note in sync if the toggle flips mid-session.
        .onChange(of: settings.focusMusic) { _, _ in
            FocusSessionController.shared.refreshVisuals()
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonCapture)) { _ in
            showingVoiceCapture = true
            HapticEngine.shared.tap()
            // Free the audio session — the mic and the ambient engine can't share it
            SpatialAudioService.shared.stop()
            voice.start()
        }
        .animation(.easeInOut(duration: 0.2), value: showingVoiceCapture)
        .animation(.easeInOut(duration: 0.25), value: progression.pendingMilestone)
        // Deference: any touch wakes the chrome; quiet hands let it rest again.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if chromeRests { withAnimation(.easeOut(duration: 0.25)) { chromeRests = false } }
                }
                .onEnded { _ in scheduleChromeRest() }
        )
        .overlay { overlayStack }
        .overlay(alignment: .bottom) { rapidChipsOverlay }
        .overlay(alignment: .topTrailing) { cornerControls.opacity(chromeRests ? 0.25 : 1) }
        .overlay(alignment: .topLeading) { moodBadgeCorner.opacity(chromeRests ? 0.25 : 1) }
        .overlay(alignment: .top) { clusterPagerCorner.opacity(chromeRests ? 0.25 : 1) }
        .overlay(alignment: .bottomTrailing) { companionCorner }
        .overlay { ScatterLayer(shots: capturer.scatterShots, mapSize: mapSize) }
        .overlay { if let w = capturer.captureWebAt, !reduceMotion { WebShotView(start: w).allowsHitTesting(false) } }
        .overlay { brainDumpOverlay }
        .overlay {
            if showAchievements {
                AchievementsView(isPresented: $showAchievements, clusters: clusters).zIndex(60)
            }
        }
    }

    /// Push a tiny cluster summary to the App Group so the Home-Screen cluster widget
    /// can show + flip through them. Nothing new leaves the device — just the names +
    /// active counts the user already sees on their map.
    private func syncWidget() {
        let ordered = clusters.sorted { $0.createdAt < $1.createdAt }
        let summaries = ordered.map { c -> ClusterSummary in
            let raw = c.effectiveHighlightHex
            let hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
            return ClusterSummary(id: c.id.uuidString, label: c.label,
                                  count: c.items.filter { $0.state != .done }.count, tintHex: hex)
        }
        SharedClusterStore.write(summaries)
        WidgetCenter.shared.reloadTimelines(ofKind: "UnstuckClusterWidget")
    }


    func dismissTeach() {
        HapticEngine.shared.tap()
        withAnimation { showingTeach = false }
        teachText = ""
    }

    func saveTeach() {
        let trimmed = teachText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(CoachingNote(text: trimmed))
        HapticEngine.shared.reward(.medium)
        withAnimation { showingTeach = false }
        teachText = ""
    }

    // MARK: - Surprise me (decision-paralysis killer)

    func surpriseMe() {
        // Fading items included — "surprise me" is exactly how a cooled thing gets a
        // second life (gentle resurfacing, fights object permanence).
        let active = clusters.flatMap { $0.items }.filter { $0.state != .done }
        guard let pick = active.randomElement() else {
            HapticEngine.shared.settle()
            return
        }
        HapticEngine.shared.reward(.rigid)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            survivalItem = pick
        }
    }

    func completeSurvival(_ item: BrainItem) {
        // Credits accrue SILENTLY here — no slot show for someone in survival mode (calm
        // floor), but the win still counts and shows up later in "look what you did".
        progression.awardCredits(estimatedMinutes: item.estimatedMinutes,
                                 wasAvoided: item.state == .fading)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            item.state = .done
            survivalItem = nil
        }
        HapticEngine.shared.complete()
        mood.recordCompletion()
        progression.recordCompletion()
        NotificationCenter.default.post(name: .taskCompleted, object: nil)
    }

    /// Deference (the Apple-minimal move): after ~7s of quiet hands, the top chrome
    /// (controls, mood badge, pager) fades to a whisper so the map is the hero. Never
    /// fully gone — object permanence matters for this audience — and any touch brings
    /// it straight back. The app literally stops asking for attention.
    private func scheduleChromeRest() {
        chromeRestTask?.cancel()
        chromeRestTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.4)) { chromeRests = true }
        }
    }

    /// A real win landed (completion or brain-dump): keep the widget current, and in
    /// insane mode pop a quick laser burst.
    private func onRealWin() {
        syncWidget()        // item counts changed
        guard settings.insaneMode else { return }
        celebrateStart = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { celebrateStart = nil }
    }

    /// "Incomplete tasks gently fade — they never accumulate guilt." Anything untouched
    /// for ~3 days cools to .fading: dimmer on the map, never red, never a count. Coming
    /// back to finish one later is worth ×2 (see Progression.awardCredits).
    private func fadeStaleItems() {
        let cutoff = Date().addingTimeInterval(-3 * 24 * 3600)
        for item in clusters.flatMap(\.items)
        where item.state == .active && item.lastTouchedAt < cutoff {
            item.state = .fading
        }
    }


    // MARK: - 🥚 Easter eggs

    private let secretLines = [
        "🎛️ the stage is yours.",
        "found it. of course you did.",
        "ok yeah — built different.",
        "go off, legend.",
        "welcome to the booth 🔊",
    ]

    // Drop a rave on demand (or a calm pulse if calm mode is on)
    private func dropTheBeat() {
        if settings.calmMode {
            HapticEngine.shared.reward(.soft)
            return
        }
        HapticEngine.shared.fling(rotationRate: 7)
        celebrateStart = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { celebrateStart = nil }
    }

    // Tap the stage 7× to reveal a secret
    private func tapYou() {
        HapticEngine.shared.tap()
        youTaps += 1
        let mine = youTaps
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if youTaps == mine { youTaps = 0 }   // reset if they stopped
        }
        if youTaps >= 7 {
            youTaps = 0
            revealSecret()
        }
    }

    private func revealSecret() {
        HapticEngine.shared.reward(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            secretMessage = secretLines.randomElement()
        }
        if !settings.calmMode {
            celebrateStart = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { celebrateStart = nil }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.easeOut(duration: 0.4)) { secretMessage = nil }
        }
    }

    // Magic words typed into capture (the thought still lands normally)
    private func checkSecretWord(_ text: String) {
        let t = text.lowercased()
        if t.contains("rave") || t.contains("disco") || t.contains("drop the beat") {
            dropTheBeat()
        } else if t.contains("squirrel") {
            // the classic distraction → the app hands you a random win instead
            HapticEngine.shared.tap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { surpriseMe() }
        } else if t.contains("dopamine") || t.contains("serotonin") {
            HapticEngine.shared.fling(rotationRate: 8)   // a big, satisfying jolt
        } else if t.contains("thwip") || t.contains("spiderman") || t.contains("spider-man") || t.contains("spidey") {
            shootWeb()
        }
    }

    // 🥚 thwip — a web shoots out from YOU across the whole map
    private func shootWeb() {
        if settings.calmMode { HapticEngine.shared.reward(.soft); return }
        HapticEngine.shared.reward(.rigid)   // sharp snap
        webStart = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { webStart = nil }
    }

    // MARK: - Focus music

    func toggleMusic() {
        HapticEngine.shared.tap()
        settings.focusMusic.toggle()
        // Music needs the engine running — ensure it's up (no-op if calm/already on)
        if settings.focusMusic { SpatialAudioService.shared.start(clusters: clusters) }
        SpatialAudioService.shared.setMusicEnabled(settings.focusMusic, mode: mood.mode)
    }

    // MARK: - Companion (fully dismissible — PDA-safe; you pull it, you can send it away)

    func toggleCompanion() {
        HapticEngine.shared.tap()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            settings.companionOn.toggle()
        }
    }

    // Mood sensing on/off — off keeps a calm neutral look (no-demand mode)
    func toggleAdaptive() {
        HapticEngine.shared.tap()
        settings.adaptiveMood.toggle()
        mood.reevaluate()   // apply immediately
    }

    // MARK: - Sensory dial (calm ↔ normal ↔ insane)

    func cycleSensory() {
        HapticEngine.shared.reward(settings.insaneMode ? .soft : .rigid)
        withAnimation(.easeInOut(duration: 0.4)) {
            settings.cycle()
        }
        if settings.calmMode {
            SpatialAudioService.shared.stop()
        } else {
            SpatialAudioService.shared.start(clusters: clusters)
        }
        // Jumping into insane throws a celebratory show immediately
        if settings.insaneMode {
            celebrateStart = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { celebrateStart = nil }
        }
    }

    // MARK: - Four-finger overview fidget

    /// Pull back to a calm bird's-eye where every cluster is visible — or drop back in.
    private func toggleOverview() {
        overviewMode.toggle()
        HapticEngine.shared.reward(.rigid)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
            if overviewMode {
                userScale   = 0.62      // zoom out to frame the whole constellation
                panOffset   = .zero
                mapRotation = .zero
            } else {
                userScale   = 1.0       // drop back into the map
            }
        }
        if overviewMode { relaxClusters(in: mapSize) }  // tidy it while we're up here
    }

    // MARK: - Collision avoidance (one-shot relaxation, no continuous physics)

    private func relaxClusters(in size: CGSize) {
        resolveOverlaps(around: nil, in: size)
    }

    /// Push apart any clusters closer than `minDist`. If `fixed` is given, that
    /// cluster stays where the user dropped it and the others move around it.
    private func resolveOverlaps(around fixed: Cluster?, in size: CGSize) {
        guard size.width > 1, clusters.count > 1 else { return }
        let minDist: CGFloat = 184      // ~card width + small gap
        let pad: CGFloat = 92           // keep cards on screen
        let fixedIdx = fixed.flatMap { f in clusters.firstIndex(where: { $0.id == f.id }) }

        var pts = clusters.map {
            CGPoint(x: $0.positionX * size.width, y: $0.positionY * size.height)
        }

        var moved = false
        for _ in 0..<14 {
            for i in 0..<pts.count {
                for j in (i + 1)..<pts.count {
                    let dx = pts[j].x - pts[i].x
                    let dy = pts[j].y - pts[i].y
                    var dist = sqrt(dx * dx + dy * dy)
                    if dist < 0.01 { dist = 0.01 }
                    guard dist < minDist else { continue }
                    moved = true
                    let push = minDist - dist
                    let ux = dx / dist, uy = dy / dist
                    let iFixed = (i == fixedIdx), jFixed = (j == fixedIdx)
                    if iFixed && jFixed { continue }
                    else if iFixed { pts[j].x += ux * push; pts[j].y += uy * push }
                    else if jFixed { pts[i].x -= ux * push; pts[i].y -= uy * push }
                    else {
                        let h = push / 2
                        pts[i].x -= ux * h; pts[i].y -= uy * h
                        pts[j].x += ux * h; pts[j].y += uy * h
                    }
                }
            }
            for k in 0..<pts.count where k != fixedIdx {
                pts[k].x = Swift.min(size.width  - pad, Swift.max(pad, pts[k].x))
                pts[k].y = Swift.min(size.height - pad, Swift.max(pad, pts[k].y))
            }
        }

        guard moved else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            for (i, c) in clusters.enumerated() {
                c.positionX = Double((pts[i].x / size.width).clamped(to: 0...1))
                c.positionY = Double((pts[i].y / size.height).clamped(to: 0...1))
            }
        }
    }

    // MARK: - Seed

    private func seedIfNeeded() {
        guard clusters.isEmpty else { return }
        let defaults: [(ZoneType, String, Double, Double)] = [
            (.reminders,      "reminders",  0.25, 0.22),
            (.health,         "health",     0.75, 0.22),
            (.timeManagement, "time",       0.25, 0.72),
            (.routines,       "routines",   0.50, 0.80),   // bottom-centre — leaves the bottom-right corner for the companion
            (.ideas,          "ideas",      0.50, 0.12),
            (.captures,       "captures",   0.12, 0.50),
            (.someday,        "someday",    0.88, 0.50),
        ]
        for (zone, label, x, y) in defaults {
            modelContext.insert(Cluster(zoneType: zone, label: label, positionX: x, positionY: y))
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

// MARK: - Milestone reveal — the focus-taking collection moment (for REAL progress)

// MARK: - Silent mood badge (ambient — colour + glyph, never the mood's name)

struct MoodBadge: View {
    let mode: BrainMode

    private var icon: String {
        switch mode {
        case .ready:      return "bolt.fill"
        case .hyperfocus: return "scope"
        case .lowBattery: return "moon.zzz.fill"
        case .overwhelm:  return "cloud.fill"
        }
    }
    private var color: Color {
        switch mode {
        case .ready:      return Color(red: 0.3, green: 0.85, blue: 0.6)
        case .hyperfocus: return Color(red: 0.45, green: 0.5, blue: 1.0)
        case .lowBattery: return Color(red: 1.0, green: 0.6, blue: 0.4)
        case .overwhelm:  return Color(red: 0.6, green: 0.66, blue: 0.78)
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(color.opacity(0.9))
            .frame(width: 40, height: 40)
            .panel(Circle(), tint: color.opacity(0.12))
            .id(mode)   // cross-fades when the mood changes
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

struct MilestoneReveal: View {
    let milestone: Milestone
    let onDismiss: () -> Void

    @State private var captionIn = false
    private let start = Date()

    // Bigger milestones throw a bigger show
    private var showIntensity: Double {
        switch milestone.tier {
        case .common:    return 0.2
        case .rare:      return 0.4
        case .epic:      return 0.6
        case .mythic:    return 0.75
        case .legendary: return 0.9
        case .chaos:     return 1.0
        }
    }

    var body: some View {
        ZStack {
            // The star-drop burst choreography
            DropBoxView(tier: milestone.tier, onBurst: {})

            // Rave laser + flame show from the YOU stage — unless calm mode is on
            if !AppSettings.shared.calmMode {
                LaserShowView(color: milestone.tier.color,
                              intensity: showIntensity,
                              start: start, duration: 2.4)
            }

            // Insight caption rises after the burst — the "oh", not just confetti
            VStack {
                Spacer()
                Text(milestone.caption)
                    .font(.system(size: 15, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 120)
                    .opacity(captionIn ? 1 : 0)
                    .offset(y: captionIn ? 0 : 12)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.75)) { captionIn = true }
            // Auto-dismiss after the moment lands
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { onDismiss() }
        }
        .onTapGesture { onDismiss() }   // tap to collect / dismiss early
    }
}
