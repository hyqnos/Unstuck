import Foundation
import SwiftUI
import Observation

@Observable
final class MoodDetector {
    private(set) var mode: BrainMode = .ready

    // Live session signals
    private var sessionStart = Date()
    private var lastInteractionAt = Date()
    private var tapIntervals: [TimeInterval] = []
    private var completions = 0
    private var interactions = 0
    private var evalTimer: Timer?

    // The user's learned personal norms (persisted, local)
    private var baseline = UserBaseline.load()
    private var hourRecorded = false

    static let shared = MoodDetector()
    private init() {}

    // MARK: - Lifecycle

    func start() {
        sessionStart = Date()
        baseline = UserBaseline.load()
        hourRecorded = false
        evalTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.tick() }
        }
        evaluate()
    }

    func stop() {
        evalTimer?.invalidate()
        // Fold this session into the long-term baseline
        let sessionMins = Date().timeIntervalSince(sessionStart) / 60
        if interactions > 2 {
            baseline.observeSession(sessionMins)
            baseline.observeCompletionRate(completionRate)
            if tapIntervals.count >= 5 { baseline.observeTapCV(tapCV) }
        }
        baseline.save()
    }

    // MARK: - Signal recording

    func recordTap() {
        let now = Date()
        let interval = now.timeIntervalSince(lastInteractionAt)
        if interval < 60 {
            tapIntervals.append(interval)
            if tapIntervals.count > 20 { tapIntervals.removeFirst() }
            // Learn the personal tap rhythm
            baseline.observeTapGap(interval)
        }
        // Learn active hours (once per session is enough signal)
        if !hourRecorded {
            baseline.observeHour(Calendar.current.component(.hour, from: now))
            hourRecorded = true
        }
        lastInteractionAt = now
        interactions += 1
        evaluate()
    }

    func recordCompletion() {
        completions += 1
        interactions += 1
        evaluate()
    }

    // MARK: - Derived

    private var completionRate: Double {
        interactions > 0 ? Double(completions) / Double(interactions) : 0.0
    }

    private var avgTapGap: Double {
        tapIntervals.isEmpty ? baseline.tapGapMean : tapIntervals.reduce(0, +) / Double(tapIntervals.count)
    }

    /// Coefficient of variation (std / mean) of recent tap intervals — how erratic
    /// the rhythm is, independent of speed. This is the intra-individual-variability
    /// marker (Kofler 2013; Karalunas 2014) — high = lapses/dysregulation, low = flow.
    private var tapCV: Double {
        guard tapIntervals.count >= 4 else { return baseline.tapCVMean }
        let mean = tapIntervals.reduce(0, +) / Double(tapIntervals.count)
        guard mean > 0 else { return baseline.tapCVMean }
        let variance = tapIntervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(tapIntervals.count)
        return variance.squareRoot() / mean
    }

    // MARK: - Periodic tick — re-evaluate + persist baseline

    private func tick() {
        if tapIntervals.count >= 5 { baseline.observeTapCV(tapCV) }
        evaluate()
        baseline.save()
    }

    // MARK: - Evaluation

    private func evaluate() {
        let hour        = Calendar.current.component(.hour, from: Date())
        let sessionMins = Date().timeIntervalSince(sessionStart) / 60

        let new = baseline.isWarmedUp
            ? classifyPersonal(hour: hour, sessionMins: sessionMins)
            : classifyGeneric(hour: hour, sessionMins: sessionMins)

        guard new != mode else { return }
        withAnimation(.easeInOut(duration: 2.0)) { mode = new }
    }

    // MARK: - Personal classification (relative to learned baseline)

    private func classifyPersonal(hour: Int, sessionMins: Double) -> BrainMode {
        let z = baseline.tapGapZ(avgTapGap)        // <0 faster than usual, >0 slower
        let cv = tapCV                             // rhythm steadiness (IIV marker)
        let rate = completionRate
        let personalRate = baseline.completionMean

        // Hyperfocus — a STEADY rhythm for YOU (flow), with things landing. Flow
        // reads as low variability, not merely speed (Kofler 2013; Karalunas 2014).
        if (baseline.cvSteady(cv) || z < -1.0) && rate >= personalRate && sessionMins > 4 {
            return .hyperfocus
        }

        // Overwhelm — an ERRATIC rhythm (attention lapses) with little landing.
        // Variability, not slowness, is the dysregulation signal: RT-variability
        // deficits persist after controlling for mean speed (Kofler 2013).
        if baseline.cvElevated(cv) && rate < personalRate * 0.5 && interactions > 5 {
            return .overwhelm
        }

        // Low battery — slower than YOUR norm, OR a personally low-energy hour,
        // OR a session far longer than you usually sustain
        let muchSlower = z > 1.3
        let lowHour    = baseline.hourIsLow(hour)
        let overrun    = sessionMins > baseline.sessionMean * 2.2
        if muchSlower || lowHour || (overrun && rate < personalRate * 0.6) {
            return .lowBattery
        }

        return .ready
    }

    // MARK: - Generic fallback (cold start, before baseline warms up)

    private func classifyGeneric(hour: Int, sessionMins: Double) -> BrainMode {
        let gap  = avgTapGap
        let cv   = tapCV
        let rate = completionRate
        // Steady rhythm OR fast + landing → flow; erratic rhythm + nothing landing → overwhelm.
        if (cv < 0.45 || gap < 1.5) && rate > 0.3 && sessionMins > 5 { return .hyperfocus }
        if (cv > 0.95 || gap < 2.0) && rate < 0.06 && interactions > 5 { return .overwhelm }
        let lateOrEarly  = hour >= 22 || hour < 7
        let afternoonDip = hour >= 13 && hour <= 15
        let slowTaps     = gap > 8.0
        let longSession  = sessionMins > 45
        if lateOrEarly || (afternoonDip && slowTaps) || (longSession && rate < 0.15) {
            return .lowBattery
        }
        return .ready
    }
}
