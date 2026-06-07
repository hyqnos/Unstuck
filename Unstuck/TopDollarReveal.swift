import SwiftUI

/// Top Dollar payout — spinning reels that land on the symbols you EARNED (🍒 / BAR / $ /
/// 777 for the jackpot), then a credit meter that ticks UP to the earned amount. The reels and
/// the count-up are pure slot-machine theatre; the result is honest — `Progression.awardCredits`
/// is a deterministic function of the real task, so the reels ALWAYS land on what you actually
/// earned. No RNG outcome, no spin-for-nothing. The brain feels "I hit it" — because you did.
/// Bottom-anchored so it never collides with the centre celebrations.
struct TopDollarReveal: View {
    let amount: Int
    let jackpot: Bool
    let total: Int
    var onDone: () -> Void = {}

    @State private var start = Date()
    @State private var shown = false
    @State private var tick = 0
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)
    private let teal = Color(red: 0.30, green: 0.85, blue: 0.75)
    private var accent: Color { jackpot ? gold : teal }

    /// The earned winning line — bigger tasks land bigger symbols. Always a match (you won it).
    private var symbols: [String] {
        if jackpot { return ["7", "7", "7"] }
        switch amount {
        case ..<15: return ["🍒", "🍒", "🍒"]
        case ..<40: return ["BAR", "BAR", "BAR"]
        default:    return ["$", "$", "$"]
        }
    }
    private let stopTimes = [0.45, 0.85, 1.25]

    var body: some View {
        VStack(spacing: 12) {
            SlotReels(symbols: symbols, stopTimes: stopTimes, accent: accent, start: start)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(jackpot ? "JACKPOT  $ 777 $" : "BONUS WIN")
                        .font(.system(size: jackpot ? 13 : 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(accent)
                    Text("\(total) credits")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text("+\(tick)")
                    .font(.system(size: jackpot ? 34 : 26, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: accent.opacity(shown ? 0.85 : 0), radius: jackpot ? 14 : 8)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(accent.opacity(0.6), lineWidth: 1.4))
        .shadow(color: accent.opacity(jackpot ? 0.45 : 0.22), radius: 12)
        .padding(.horizontal, 26)
        .offset(y: shown ? 0 : 180)
        .opacity(shown ? 1 : 0)
        .onAppear { run() }
    }

    private func run() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.74)) { shown = true }

        // A "clunk" as each reel stops, left → right.
        for s in stopTimes {
            DispatchQueue.main.asyncAfter(deadline: .now() + s) { HapticEngine.shared.reward(.rigid) }
        }

        // After the reels land, the credits roll UP to the earned amount.
        let countStart = (stopTimes.last ?? 1.25) + 0.18
        let steps = min(max(amount, 1), 24)
        let dt = jackpot ? 0.035 : 0.022
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + countStart + Double(i) * dt) {
                tick = Int(Double(amount) * Double(i) / Double(steps))
                if i % 3 == 0 { HapticEngine.shared.tap() }
            }
        }
        let landAt = countStart + Double(steps) * dt + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + landAt) {
            tick = amount
            HapticEngine.shared.reward(jackpot ? .rigid : .medium)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + landAt + (jackpot ? 1.8 : 1.2)) {
            withAnimation(.easeIn(duration: 0.35)) { shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onDone() }
        }
    }
}

/// Three reels that cycle fast, then lock left→right onto the earned symbols. The cycling is a
/// visual blur only (the outcome is fixed) — driven by a TimelineView, no timers to leak.
private struct SlotReels: View {
    let symbols: [String]
    let stopTimes: [Double]
    let accent: Color
    let start: Date
    private let pool = ["🍒", "BAR", "7", "$", "★", "2×"]

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    let stopped = t >= stopTimes[i]
                    let sym = stopped ? symbols[i] : pool[(Int(t * 20) + i * 3) % pool.count]
                    Text(sym)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .frame(width: 50, height: 52)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(accent.opacity(stopped ? 0.9 : 0.25), lineWidth: stopped ? 2 : 1))
                        .scaleEffect(stopped ? 1.0 : 0.95)
                        .shadow(color: accent.opacity(stopped ? 0.5 : 0), radius: 6)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: stopped)
                }
            }
        }
        .frame(height: 54)
    }
}
