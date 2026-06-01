import Foundation

/// The user's learned personal norms — built up locally over time, never leaves the device.
/// Mood is judged against THIS person's baseline, not generic thresholds.
/// Uses exponential moving averages so old habits fade and the baseline tracks the
/// current self (also fights novelty death — the app keeps re-learning you).
struct UserBaseline: Codable {
    // Tap rhythm — mean + variance via exponentially-weighted estimators
    var tapGapMean: Double = 4.0
    var tapGapVar:  Double = 4.0      // std starts ~2s

    // Intra-individual variability — the coefficient of variation (std/mean) of
    // tap intervals: how *erratic* the rhythm is, independent of how fast it is.
    // This is the single most-replicated behavioural marker in the literature:
    // erratic timing (high CV, "lapses of attention") indexes dysregulation, while
    // steady timing (low CV) tracks flow/hyperfocus — and crucially it matters
    // *more than mean speed*. In autism it's elevated mainly where ADHD co-occurs,
    // i.e. exactly this app's brain. We learn the PERSONAL norm, never a generic cut.
    //   • Kofler, Rapport, Sarver et al. (2013), "Reaction time variability in ADHD:
    //     a meta-analytic review of 319 studies", Clinical Psychology Review 33(6),
    //     795–811. doi:10.1016/j.cpr.2013.06.001
    //     (RT-variability deficits remain after controlling for mean RT; mean-RT
    //      differences vanish after controlling for variability.)
    //   • Karalunas, Geurts, Konrad, Bender & Nigg (2014), "Annual Research Review:
    //     Reaction time variability in ADHD and autism spectrum disorders…",
    //     J. Child Psychol. & Psychiatry 55(6), 685–710. doi:10.1111/jcpp.12217
    //     (a proposed trans-diagnostic ADHD↔autism phenotype.)
    var tapCVMean: Double = 0.6

    // Completion rhythm (done / interactions)
    var completionMean: Double = 0.15

    // Session length the user typically sustains (minutes)
    var sessionMean: Double = 8.0

    // Activity by hour-of-day — which hours this brain is actually awake/engaged
    var hourActivity: [Double] = Array(repeating: 0, count: 24)

    // How many tap-rhythm samples we've seen — gates the personal model
    var sampleCount: Int = 0

    // MARK: - Derived

    var tapGapStd: Double { max(0.4, sqrt(tapGapVar)) }
    var isWarmedUp: Bool { sampleCount >= 25 }

    /// Signed deviation of a tap gap from the personal norm (in std units).
    /// Negative = faster than usual, positive = slower than usual.
    func tapGapZ(_ gap: Double) -> Double {
        (gap - tapGapMean) / tapGapStd
    }

    /// Rhythm noticeably more erratic than this person's norm — the attention-lapse
    /// signal (the exponential/"tau" component of RT variability). → dysregulation.
    func cvElevated(_ cv: Double) -> Bool { cv > tapCVMean * 1.35 }
    /// Rhythm noticeably steadier than usual — locked-in / flow.
    func cvSteady(_ cv: Double) -> Bool { cv < tapCVMean * 0.70 }

    /// Is the current hour a personally low-energy hour? (needs enough history)
    func hourIsLow(_ hour: Int) -> Bool {
        let total = hourActivity.reduce(0, +)
        guard total > 40 else { return false }
        let avg = total / 24
        return hourActivity[hour] < avg * 0.4
    }

    // MARK: - Online learning (EMA / EW-variance)

    mutating func observeTapGap(_ gap: Double) {
        let a = 0.06   // ~16-sample memory
        let delta = gap - tapGapMean
        tapGapMean += a * delta
        tapGapVar  = (1 - a) * (tapGapVar + a * delta * delta)
        sampleCount += 1
    }

    /// Fold a session's coefficient of variation into the personal norm.
    mutating func observeTapCV(_ cv: Double) {
        guard cv.isFinite, cv > 0 else { return }
        tapCVMean += 0.08 * (cv - tapCVMean)
    }

    mutating func observeCompletionRate(_ rate: Double) {
        completionMean += 0.1 * (rate - completionMean)
    }

    mutating func observeSession(_ minutes: Double) {
        sessionMean += 0.15 * (minutes - sessionMean)
    }

    mutating func observeHour(_ hour: Int) {
        for i in 0..<24 { hourActivity[i] *= 0.9995 }  // slow decay
        hourActivity[hour] += 1
    }

    // MARK: - Persistence (local, private)

    private static let key = "unstuck.userBaseline"

    static func load() -> UserBaseline {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(UserBaseline.self, from: data)
        else { return UserBaseline() }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
