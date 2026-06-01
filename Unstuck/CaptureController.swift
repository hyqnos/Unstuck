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
}
