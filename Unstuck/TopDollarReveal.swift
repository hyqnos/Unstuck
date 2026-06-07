import SwiftUI

/// Top Dollar credit payout — a bottom credit-meter that ticks UP to the **earned** amount.
/// The count-up is the slot-machine theatre; the destination is honest (`Progression.awardCredits`
/// is a deterministic function of the real task — no RNG, no spin-for-nothing). Wall tasks land the
/// 777/$$$ jackpot. Sits at the bottom so it never collides with the centre celebrations.
struct TopDollarReveal: View {
    let amount: Int
    let jackpot: Bool
    let total: Int
    var onDone: () -> Void = {}

    @State private var shown = false
    @State private var tick = 0
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)
    private let teal = Color(red: 0.30, green: 0.85, blue: 0.75)
    private var accent: Color { jackpot ? gold : teal }

    var body: some View {
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
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(accent.opacity(0.6), lineWidth: 1.4))
        .shadow(color: accent.opacity(jackpot ? 0.45 : 0.22), radius: 10)
        .padding(.horizontal, 30)
        .offset(y: shown ? 0 : 150)
        .opacity(shown ? 1 : 0)
        .onAppear { run() }
    }

    private func run() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { shown = true }

        // Tick the meter UP to the earned amount — the "credits rolling in" feel, with reel ticks.
        let steps = min(max(amount, 1), 24)
        let dt = jackpot ? 0.035 : 0.022
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 + Double(i) * dt) {
                tick = Int(Double(amount) * Double(i) / Double(steps))
                if i % 3 == 0 { HapticEngine.shared.tap() }
            }
        }
        let landAt = 0.2 + Double(steps) * dt + 0.04
        DispatchQueue.main.asyncAfter(deadline: .now() + landAt) {
            tick = amount
            HapticEngine.shared.reward(jackpot ? .rigid : .medium)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + landAt + (jackpot ? 2.0 : 1.3)) {
            withAnimation(.easeIn(duration: 0.35)) { shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onDone() }
        }
    }
}
