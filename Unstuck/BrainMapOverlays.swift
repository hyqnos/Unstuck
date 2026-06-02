import SwiftUI
import SwiftData

extension BrainMapView {
    // MARK: - Extracted overlays (keep `body` under the type-checker's limit)

    @ViewBuilder var introOverlay: some View {
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

    @ViewBuilder var celebrateOverlay: some View {
        if let s = celebrateStart {
            LaserShowView(color: Color(red: 1.0, green: 0.2, blue: 0.5),
                          intensity: 1.0, start: s, duration: 1.5, insane: true)
                .zIndex(44)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder var secretOverlay: some View {
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

    @ViewBuilder var webOverlay: some View {
        if let s = webStart {
            WebShotView(start: s)
                .zIndex(47)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder var milestoneOverlay: some View {
        if let m = progression.pendingMilestone {
            MilestoneReveal(milestone: m) {
                progression.pendingMilestone = nil
            }
            .transition(.opacity)
            .zIndex(50)
        }
    }

    @ViewBuilder var onboardingOverlay: some View {
        if showOnboarding {
            OnboardingView {
                settings.hasOnboarded = true
                withAnimation(.easeInOut(duration: 0.6)) { showOnboarding = false }
            }
            .transition(.opacity)
            .zIndex(60)
        }
    }

    @ViewBuilder var voiceOverlay: some View {
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

    @ViewBuilder var dropBoxOverlay: some View {
        if let drop = capturer.pendingDrop {
            DropBoxView(tier: drop.tier, onBurst: { })
                .transition(.opacity)
                .zIndex(30)
        }
    }

    @ViewBuilder var rapidChipsOverlay: some View {
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

    @ViewBuilder var detailOverlay: some View {
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

    @ViewBuilder var survivalOverlay: some View {
        if let item = survivalItem {
            SurvivalBanner(item: item,
                onDone: { completeSurvival(item) },
                onRelease: { withAnimation { survivalItem = nil } })
                .transition(.opacity)
                .zIndex(15)
        }
    }

    @ViewBuilder var teachOverlayWrap: some View {
        if showingTeach {
            teachOverlay
                .transition(.opacity)
                .zIndex(25)
        }
    }

    @ViewBuilder var breadcrumbOverlayWrap: some View {
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

    @ViewBuilder var focusOverlay: some View {
        if FocusSessionController.shared.isActive {
            FocusPill(session: FocusSessionController.shared)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(55)
        }
    }

    // All full-screen overlays in one ZStack (zIndex orders them) — keeps body short
    @ViewBuilder var overlayStack: some View {
        ZStack {
            focusOverlay
            voiceOverlay
            dropBoxOverlay
            introOverlay
            celebrateOverlay
            secretOverlay
            webOverlay
            milestoneOverlay
            detailOverlay
            survivalOverlay
            teachOverlayWrap
            breadcrumbOverlayWrap
            onboardingOverlay
        }
    }

    @ViewBuilder var cornerControls: some View {
        if survivalItem == nil && !showingBreadcrumbs {
            quietControls
                .padding(.trailing, 20)
                .padding(.top, 58)
        }
    }

    @ViewBuilder var moodBadgeCorner: some View {
        if survivalItem == nil && !showingBreadcrumbs {
            MoodBadge(mode: mood.mode)
                .padding(.leading, 20)
                .padding(.top, 58)
                .animation(.easeInOut(duration: 0.6), value: mood.mode)
        }
    }

    // MARK: - Quiet controls (surprise-me / teach)

    var quietControls: some View {
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

    var teachOverlay: some View {
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
}
