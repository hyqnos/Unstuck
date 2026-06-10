import SwiftUI
import SwiftData

// A lightweight chip shown for rapid (non-blocking) captures
struct RapidChip: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let tint: Color
}

/// Owns the whole capture flow + its transient animation state, so BrainMapView
/// doesn't. Two paths: a calm full-celebration drop, and a non-blocking rapid chip
/// for brain-dumps. Drives the focus-dive zoom, the drop box, and surprise chaos bursts.
@MainActor
@Observable
final class CaptureController {
    enum DropPhase: Equatable {
        case idle
        case zoomOut
        case zoomIn(ax: CGFloat, ay: CGFloat)
    }

    // Visual state the map reads
    var dropPhase: DropPhase = .idle
    var highlightID: UUID? = nil
    var pendingDrop: (text: String, tier: DropTier)? = nil
    var rapidChips: [RapidChip] = []
    var captureWebAt: Date? = nil           // a web flickers across the map as a thought lands

    // Internal cadence tracking
    private var chaosCount = 0
    private var lastCaptureTime = Date()

    private let classifier = ClusterClassifier.shared
    private let progression = Progression.shared

    // MARK: - Map reads these for the zoom transform

    var diveScale: CGFloat {
        switch dropPhase {
        case .idle:    return 1.0
        case .zoomOut: return 0.45
        case .zoomIn:  return 1.65
        }
    }

    var diveAnchor: UnitPoint {
        if case .zoomIn(let ax, let ay) = dropPhase {
            return UnitPoint(x: ax, y: ay)
        }
        return .center
    }

    // MARK: - Capture
    //
    //  • Calm capture (first after a lull, or just one): full star-drop + focus-dive zoom.
    //  • Rapid capture (within 4s, or while one is mid-flight): a fast, NON-BLOCKING
    //    chip that flies to its cluster. Every ~6th rapid one bursts a surprise.

    func capture(text: String, clusters: [Cluster], context: ModelContext) async {
        let now = Date()
        let rapid = now.timeIntervalSince(lastCaptureTime) < 4.0 || pendingDrop != nil
        lastCaptureTime = now

        let result = await classifier.classifyAndName(text: text)
        let target = clusters.first(where: { $0.zoneType == result.zone })
            ?? clusters.first(where: { $0.zoneType == .captures })
            ?? clusters.first
        guard let target else { return }

        // A web thwips across the map as the thought is caught (skipped in calm mode).
        // WebShotView's own life is grow(0.36s) → hold → fade(0.9–1.6s); clear AFTER the
        // fade finishes or it pops off at full alpha.
        if !AppSettings.shared.calmMode {
            let stamp = Date()
            captureWebAt = stamp
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak self] in
                if self?.captureWebAt == stamp { self?.captureWebAt = nil }   // don't clear a newer one
            }
        }

        let item = BrainItem(text: text, title: result.title, cluster: target)
        context.insert(item)
        progression.recordCapture()

        if rapid {
            chaosCount += 1
            // Insane mode bursts far more often; calm mode never
            let cadence = AppSettings.shared.insaneMode ? 3 : 6
            if chaosCount % cadence == 0 && !AppSettings.shared.calmMode { surpriseBurst() }
            rapidFlash(text: text, target: target)
            return
        }

        // ── Calm capture — the full celebration ──────────────────
        chaosCount = 1
        let tier = DropTier.tier(for: target.zoneType)

        withAnimation(.easeIn(duration: 0.15)) {
            pendingDrop = (text: text, tier: tier)
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) { cont.resume() }
        }
        withAnimation { pendingDrop = nil }

        dropPhase = .zoomOut
        try? await Task.sleep(nanoseconds: 200_000_000)
        dropPhase = .zoomIn(ax: target.positionX, ay: target.positionY)
        highlightID = target.id
        HapticEngine.shared.land()
        SpatialAudioService.shared.playBlip(.land, atX: target.positionX, y: target.positionY)

        try? await Task.sleep(nanoseconds: 420_000_000)
        dropPhase = .idle
        HapticEngine.shared.reward()

        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation(.easeOut(duration: 0.3)) { highlightID = nil }
    }

    // MARK: - Private

    private func rapidFlash(text: String, target: Cluster) {
        HapticEngine.shared.reward(.light)
        SpatialAudioService.shared.playBlip(.land, atX: target.positionX, y: target.positionY)
        let chip = RapidChip(text: text, tint: target.zoneType.isOrganized
            ? .white.opacity(0.12)
            : Color(red: 0.3, green: 0.85, blue: 0.75).opacity(0.14))

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            rapidChips.append(chip)
            highlightID = target.id
        }
        let targetID = target.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) {
                self?.rapidChips.removeAll { $0.id == chip.id }
                if self?.highlightID == targetID { self?.highlightID = nil }
            }
        }
    }

    private func surpriseBurst() {
        withAnimation(.easeIn(duration: 0.12)) {
            pendingDrop = (text: "", tier: .chaos)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            withAnimation { self?.pendingDrop = nil }
        }
    }

    // MARK: - Brain-dump valve (stream everything, the funnel sorts it, then shotgun-scatter)

    /// One flying item in the scatter — knows its destination cluster + that cluster's colour.
    struct ScatterShot: Identifiable {
        let id = UUID()
        let targetX: CGFloat
        let targetY: CGFloat
        let tint: Color
        let index: Int          // for the staggered "ratatat"
    }
    var scatterShots: [ScatterShot] = []
    var dumpWhy: String? = nil   // the relief line, after they all land

    /// Empty-your-head: split a stream into items, funnel each through the classifier, drop
    /// them, then FIRE them onto the board in a staggered shotgun scatter with a haptic cascade.
    func dump(text: String, clusters: [Cluster], context: ModelContext) async {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty, !clusters.isEmpty else { return }

        // Funnel each item (on-device). Sequential — the classifier is an actor anyway.
        var shots: [ScatterShot] = []
        for (i, line) in lines.enumerated() {
            let r = await classifier.classifyAndName(text: line)
            let target = clusters.first(where: { $0.zoneType == r.zone })
                ?? clusters.first(where: { $0.zoneType == .captures })
                ?? clusters.first
            guard let target else { continue }
            context.insert(BrainItem(text: line, title: r.title, cluster: target))
            progression.recordCapture()
            shots.append(ScatterShot(targetX: target.positionX, targetY: target.positionY,
                                     tint: Color(hex: target.effectiveHighlightHex), index: i))
        }
        guard !shots.isEmpty else { return }

        // FIRE 🔫 — the boom, then the staggered scatter; a haptic + blip as each one lands.
        HapticEngine.shared.reward(.rigid)
        SpatialAudioService.shared.playBlip(.open, atX: 0.5, y: 0.5)
        withAnimation(.easeOut(duration: 0.2)) { scatterShots = shots }

        for s in shots {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(s.index) * 0.04) {
                HapticEngine.shared.land()
                SpatialAudioService.shared.playBlip(.land, atX: s.targetX, y: s.targetY)
            }
        }

        // After the last lands → relief + the WHY (the deepest hit); the companion celebrates.
        try? await Task.sleep(for: .seconds(0.25 + Double(shots.count) * 0.04 + 0.7))
        HapticEngine.shared.reward(.success)
        // A dump is a batch of CAPTURES, not a completion — its own signal, same celebration.
        NotificationCenter.default.post(name: .brainDumped, object: nil)
        let n = shots.count
        withAnimation(.easeIn(duration: 0.4)) {
            dumpWhy = "that's \(n) thing\(n == 1 ? "" : "s") out of your head. working memory just got lighter."
        }
        withAnimation(.easeOut(duration: 0.5)) { scatterShots = [] }

        try? await Task.sleep(for: .seconds(3.2))
        withAnimation(.easeOut(duration: 0.6)) { dumpWhy = nil }
    }
}
