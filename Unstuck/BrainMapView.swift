import SwiftUI
import SwiftData

struct BrainMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var clusters: [Cluster]
    @Query(sort: \CoachingNote.timesShown) private var coachingNotes: [CoachingNote]

    // Capture flow + its transient animation state lives here
    @State private var capturer = CaptureController()

    // Canvas pan + zoom + rotation
    @State private var panOffset: CGSize = .zero
    @State private var userScale: CGFloat = 1.0
    @State private var mapRotation: Angle = .zero
    @GestureState private var gestureRotation: Angle = .zero   // feeds the tilt layer

    // Overlays
    @State private var focusedCluster: Cluster? = nil
    @State private var showingVoiceCapture = false
    @State private var mapSize: CGSize = .zero         // cached for collision-avoidance
    @State private var overviewMode = false            // four-finger constellation overview
    @State private var showIntro = false               // launch laser show
    @State private var introStart = Date()
    @State private var celebrateStart: Date? = nil     // per-completion rave (insane mode)
    @State private var youTaps = 0                     // 🥚 secret stage taps
    @State private var secretMessage: String? = nil
    @State private var showOnboarding = !AppSettings.shared.hasOnboarded
    private var voice = VoiceCapture()
    private let motion = MotionAdaptor.shared
    private let mood   = MoodDetector.shared

    private let patterns   = PatternService.shared
    private let returnState = ReturnState.shared
    private let progression = Progression.shared
    private let settings   = AppSettings.shared

    // Phase 6 — paralysis support
    @State private var showingBreadcrumbs = false
    @State private var survivalItem: BrainItem? = nil   // the one glowing thing
    @State private var showingTeach = false
    @State private var teachText = ""

    private var theme: MoodTheme { MoodTheme.theme(for: mood.mode) }

    // A tiny, climbable win — shortest active item, prefers ones with a time estimate
    private var easyWin: BrainItem? {
        let active = clusters.flatMap { $0.items }.filter { $0.state == .active }
        return active.sorted { a, b in
            let am = a.estimatedMinutes ?? 999
            let bm = b.estimatedMinutes ?? 999
            if am != bm { return am < bm }
            return a.text.count < b.text.count
        }.first
    }

    // True until the very first thought lands — drives the cold-open hint
    private var isMapEmpty: Bool {
        clusters.allSatisfy { $0.items.isEmpty }
    }

    // Sensory-dial button appearance
    private var sensoryIcon: String {
        switch settings.sensory {
        case .calm:   return "moon.fill"
        case .normal: return "moon"
        case .insane: return "flame.fill"
        }
    }
    private var sensoryTint: Color {
        switch settings.sensory {
        case .calm:   return .white
        case .normal: return .white.opacity(0.55)
        case .insane: return Color(red: 1.0, green: 0.35, blue: 0.2)
        }
    }

    // The user's own recent words
    private var ownWords: [BrainItem] {
        clusters.flatMap { $0.items }
            .filter { $0.state != .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // Whether it's a "good day" — when teach-the-app gently offers itself
    private var isGoodDay: Bool {
        mood.mode == .ready || mood.mode == .hyperfocus
    }

    // Most urgent cluster for overwhelm mode
    private var mostUrgentCluster: Cluster? {
        clusters.max(by: { a, b in
            let aUrgency = a.items.filter { $0.state == .active }.map(\.urgency).max() ?? 0
            let bUrgency = b.items.filter { $0.state == .active }.map(\.urgency).max() ?? 0
            return aUrgency < bUrgency
        })
    }

    // Manual rotation only — gyro tilt is handled inside TiltLayer (isolated 60Hz view)
    private var manualRotation: Angle { mapRotation + gestureRotation }

    // MARK: - Extracted overlays (keep `body` under the type-checker's limit)

    @ViewBuilder private var introOverlay: some View {
        if showIntro {
            LaserShowView(color: settings.insaneMode
                            ? Color(red: 1.0, green: 0.35, blue: 0.2)
                            : Color(red: 0.3, green: 0.85, blue: 0.75),
                          intensity: settings.insaneMode ? 1.0 : 0.7,
                          start: introStart,
                          duration: settings.insaneMode ? 4.0 : 2.4,
                          insane: settings.insaneMode)
                .zIndex(45)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var celebrateOverlay: some View {
        if let s = celebrateStart {
            LaserShowView(color: Color(red: 1.0, green: 0.2, blue: 0.5),
                          intensity: 1.0, start: s, duration: 1.5, insane: true)
                .zIndex(44)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var secretOverlay: some View {
        if let msg = secretMessage {
            Text(msg)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .panel(Capsule())
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .offset(y: -70)
                .zIndex(46)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var milestoneOverlay: some View {
        if let m = progression.pendingMilestone {
            MilestoneReveal(milestone: m) {
                progression.pendingMilestone = nil
            }
            .transition(.opacity)
            .zIndex(50)
        }
    }

    @ViewBuilder private var onboardingOverlay: some View {
        if showOnboarding {
            OnboardingView {
                settings.hasOnboarded = true
                withAnimation(.easeInOut(duration: 0.6)) { showOnboarding = false }
            }
            .transition(.opacity)
            .zIndex(60)
        }
    }

    @ViewBuilder private var voiceOverlay: some View {
        if showingVoiceCapture {
            VoiceCaptureOverlay(
                voice: voice,
                onDone: { text in
                    showingVoiceCapture = false
                    SpatialAudioService.shared.start(clusters: clusters)
                    Task { await capturer.capture(text: text, clusters: clusters, context: modelContext) }
                },
                onCancel: {
                    showingVoiceCapture = false
                    SpatialAudioService.shared.start(clusters: clusters)
                }
            )
            .transition(.opacity)
            .zIndex(20)
        }
    }

    @ViewBuilder private var dropBoxOverlay: some View {
        if let drop = capturer.pendingDrop {
            DropBoxView(tier: drop.tier, onBurst: { })
                .transition(.opacity)
                .zIndex(30)
        }
    }

    @ViewBuilder private var rapidChipsOverlay: some View {
        VStack(spacing: 6) {
            ForEach(capturer.rapidChips) { chip in
                Text(chip.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .panel(Capsule(), tint: chip.tint)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.7).combined(with: .opacity),
                        removal: .offset(y: -70).combined(with: .opacity)
                    ))
            }
        }
        .padding(.bottom, 88)
        .allowsHitTesting(false)
        .zIndex(28)
    }

    @ViewBuilder private var detailOverlay: some View {
        if let cluster = focusedCluster {
            ClusterDetailView(cluster: cluster) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    focusedCluster = nil
                }
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.15,
                    anchor: UnitPoint(x: cluster.positionX, y: cluster.positionY))
                    .combined(with: .opacity),
                removal: .scale(scale: 0.15,
                    anchor: UnitPoint(x: cluster.positionX, y: cluster.positionY))
                    .combined(with: .opacity)
            ))
            .zIndex(10)
        }
    }

    @ViewBuilder private var survivalOverlay: some View {
        if let item = survivalItem {
            SurvivalBanner(item: item,
                onDone: { completeSurvival(item) },
                onRelease: { withAnimation { survivalItem = nil } })
                .transition(.opacity)
                .zIndex(15)
        }
    }

    @ViewBuilder private var teachOverlayWrap: some View {
        if showingTeach {
            teachOverlay
                .transition(.opacity)
                .zIndex(25)
        }
    }

    @ViewBuilder private var breadcrumbOverlayWrap: some View {
        if showingBreadcrumbs {
            BreadcrumbOverlay(
                ownWords: ownWords,
                easyWin: easyWin,
                coachingNote: coachingNotes.first,
                onPickItem: { item in
                    coachingNotes.first.map { $0.timesShown += 1 }
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showingBreadcrumbs = false
                        survivalItem = item
                    }
                    returnState.dismissFreeze()
                },
                onEnterMap: {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        showingBreadcrumbs = false
                    }
                    returnState.dismissFreeze()
                    SpatialAudioService.shared.start(clusters: clusters)
                }
            )
            .transition(.opacity)
            .zIndex(40)
        }
    }

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
            motion.start()
            mood.start()
            patterns.analyse(clusters: clusters)

            // Phase 6 — silently check if returning from a freeze
            returnState.recordOpen()
            if returnState.returningFromFreeze && !ownWords.isEmpty {
                showingBreadcrumbs = true
            }

            // Spatial audio only when NOT in breadcrumb mode (keep return calm + quiet).
            // Setup runs on a background queue internally — safe to call directly.
            if !showingBreadcrumbs {
                SpatialAudioService.shared.start(clusters: clusters)
            }

            // Welcome rave on launch — brief, non-blocking, skipped in calm mode,
            // during a freeze-return, and on the very first run (meet the calm map first).
            if !settings.calmMode && !showingBreadcrumbs && !showOnboarding {
                introStart = Date()
                showIntro = true
                HapticEngine.shared.reward(.rigid)
                let introLen = settings.insaneMode ? 4.0 : 2.6
                DispatchQueue.main.asyncAfter(deadline: .now() + introLen) { showIntro = false }
            }
        }
        // Insane mode — every completion pops a quick laser burst
        .onReceive(NotificationCenter.default.publisher(for: .taskCompleted)) { _ in
            guard settings.insaneMode else { return }
            celebrateStart = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { celebrateStart = nil }
        }
        // App icon reflects the mood you leave in (changed on background to avoid
        // interrupting mid-session with iOS's icon-change alert)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                AppIconManager.update(for: mood.mode)
            }
        }
        // Focus music re-tunes itself live as the brain mode shifts
        .onChange(of: mood.mode) { _, newMode in
            if settings.focusMusic {
                SpatialAudioService.shared.setMood(newMode)
            }
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
        .overlay { overlayStack }
        .overlay(alignment: .bottom) { rapidChipsOverlay }
        .overlay(alignment: .topTrailing) { cornerControls }
        .overlay(alignment: .topLeading) { moodBadgeCorner }
    }

    // All full-screen overlays in one ZStack (zIndex orders them) — keeps body short
    @ViewBuilder private var overlayStack: some View {
        ZStack {
            voiceOverlay
            dropBoxOverlay
            introOverlay
            celebrateOverlay
            secretOverlay
            milestoneOverlay
            detailOverlay
            survivalOverlay
            teachOverlayWrap
            breadcrumbOverlayWrap
            onboardingOverlay
        }
    }

    @ViewBuilder private var cornerControls: some View {
        if survivalItem == nil && !showingBreadcrumbs {
            quietControls
                .padding(.trailing, 20)
                .padding(.top, 58)
        }
    }

    @ViewBuilder private var moodBadgeCorner: some View {
        if survivalItem == nil && !showingBreadcrumbs {
            MoodBadge(mode: mood.mode)
                .padding(.leading, 20)
                .padding(.top, 58)
                .animation(.easeInOut(duration: 0.6), value: mood.mode)
        }
    }

    // MARK: - Quiet controls (surprise-me / teach)

    private var quietControls: some View {
        HStack(spacing: 12) {
            // Sensory dial — tap to cycle calm → normal → insane
            Button(action: cycleSensory) {
                Image(systemName: sensoryIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(sensoryTint.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .panel(Circle(), tint: settings.sensory == .normal ? nil : sensoryTint.opacity(0.12))
            }

            // Focus music — mood-reactive ambient bed
            Button(action: toggleMusic) {
                Image(systemName: settings.focusMusic ? "music.note" : "music.note.list")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(settings.focusMusic ? 0.85 : 0.5))
                    .frame(width: 40, height: 40)
                    .panel(Circle(), tint: settings.focusMusic ? .white.opacity(0.1) : nil)
            }

            // Surprise me — kills decision paralysis
            Button(action: surpriseMe) {
                Image(systemName: "dice")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 40, height: 40)
                    .panel(Circle())
            }

            // Teach the app — only on good days
            if isGoodDay {
                Button {
                    HapticEngine.shared.tap()
                    withAnimation { showingTeach = true }
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 40, height: 40)
                        .panel(Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Teach overlay

    private var teachOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { dismissTeach() }

            VStack(spacing: 20) {
                Text("a good-day thought")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Text("something you'd want to hear\non a harder day")
                    .font(.system(size: 15, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                TextField("", text: $teachText, axis: .vertical)
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3, reservesSpace: true)
                    .padding(16)
                    .panel(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 30)

                HStack(spacing: 24) {
                    Button("not now") { dismissTeach() }
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                    Button("keep it") { saveTeach() }
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(teachText.isEmpty ? 0.2 : 0.85))
                        .disabled(teachText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func dismissTeach() {
        HapticEngine.shared.tap()
        withAnimation { showingTeach = false }
        teachText = ""
    }

    private func saveTeach() {
        let trimmed = teachText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(CoachingNote(text: trimmed))
        HapticEngine.shared.reward(.medium)
        withAnimation { showingTeach = false }
        teachText = ""
    }

    // MARK: - Surprise me (decision-paralysis killer)

    private func surpriseMe() {
        let active = clusters.flatMap { $0.items }.filter { $0.state == .active }
        guard let pick = active.randomElement() else {
            HapticEngine.shared.settle()
            return
        }
        HapticEngine.shared.reward(.rigid)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            survivalItem = pick
        }
    }

    private func completeSurvival(_ item: BrainItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            item.state = .done
            survivalItem = nil
        }
        HapticEngine.shared.complete()
        mood.recordCompletion()
        progression.recordCompletion()
        NotificationCenter.default.post(name: .taskCompleted, object: nil)
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
        }
    }

    // MARK: - Focus music

    private func toggleMusic() {
        HapticEngine.shared.tap()
        settings.focusMusic.toggle()
        // Music needs the engine running — ensure it's up (no-op if calm/already on)
        if settings.focusMusic { SpatialAudioService.shared.start(clusters: clusters) }
        SpatialAudioService.shared.setMusicEnabled(settings.focusMusic, mode: mood.mode)
    }

    // MARK: - Sensory dial (calm ↔ normal ↔ insane)

    private func cycleSensory() {
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
            (.routines,       "routines",   0.75, 0.72),
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

private struct MoodBadge: View {
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

private struct MilestoneReveal: View {
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
