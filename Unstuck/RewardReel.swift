import SwiftUI

/// The big-tier reveal for the hardest tasks. A reel of cards spins fast, then
/// decelerates with ticking anticipation, and lands on YOUR reward: the WHY — a line
/// of real brain science about finishing something hard.
///
/// The craft (the spin, the slowing tick, the landing) is pure presentation. The
/// payoff is NEVER random — it always lands on the insight tied to the task you
/// actually finished. No mystery box, no spin-for-nothing: that variable-ratio loop
/// is exactly the cheap, tank-draining dopamine this app exists to protect against.
/// The anticipation is honest, and the deepest hit (the insight) is the part a slot
/// machine can't give.
struct RewardReel: View {
    let whyLine: String
    var onDone: () -> Void

    private let step: CGFloat = 86
    private let cardW: CGFloat = 78
    private let landIndex = 17

    @State private var centeredIndex: Double = 0
    @State private var landed = false
    @State private var showWhy = false

    private let tint = Color(red: 0.30, green: 0.95, blue: 0.70)
    private let gold = Color(red: 1.00, green: 0.82, blue: 0.35)

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
                .onTapGesture { if landed { onDone() } }

            VStack(spacing: 20) {
                Text("a wall came down")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(gold.opacity(0.9))

                GeometryReader { geo in
                    ZStack {
                        HStack(spacing: step - cardW) {
                            ForEach(0...(landIndex + 3), id: \.self) { i in card(i) }
                        }
                        .offset(x: geo.size.width / 2 - cardW / 2 - CGFloat(centeredIndex) * step)

                        // Centre marker
                        Rectangle().fill(gold.opacity(0.9)).frame(width: 2, height: 116)
                        Image(systemName: "arrowtriangle.down.fill")
                            .foregroundStyle(gold).font(.system(size: 12)).offset(y: -66)
                        Image(systemName: "arrowtriangle.up.fill")
                            .foregroundStyle(gold).font(.system(size: 12)).offset(y: 66)
                    }
                    .frame(height: 120)
                    .clipped()
                }
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))

                if showWhy {
                    VStack(spacing: 8) {
                        Text(whyLine)
                            .font(.system(size: 13, weight: .light, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("tap to close")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(24)
        }
        .task { await spin() }
    }

    private func card(_ i: Int) -> some View {
        let isWin = i == landIndex
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: isWin ? [gold, gold.opacity(0.55)] : [tint.opacity(0.5), tint.opacity(0.18)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke((isWin ? gold : tint).opacity(0.8), lineWidth: isWin ? 2 : 1))
                .shadow(color: (isWin ? gold : tint).opacity(0.5), radius: isWin ? 12 : 4)
            Image(systemName: isWin ? "star.fill" : "sparkle")
                .font(.system(size: isWin ? 26 : 18))
                .foregroundStyle(.white.opacity(isWin ? 1 : 0.7))
        }
        .frame(width: cardW, height: 96)
        .scaleEffect(isWin && landed ? 1.12 : 1.0)
    }

    @MainActor private func spin() async {
        let calm = AppSettings.shared.calmMode
        // Each step's gap GROWS toward the end → the reel decelerates (ease-out).
        for i in 1...landIndex {
            let f = Double(i) / Double(landIndex)
            let interval = 0.04 + 0.30 * pow(f, 2.2)
            withAnimation(.easeOut(duration: interval)) { centeredIndex = Double(i) }
            if !calm { HapticEngine.shared.tap() }          // a tick per card crossing
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }
        }
        if calm { HapticEngine.shared.reward(.medium) } else { HapticEngine.shared.claimBurst(big: true) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { landed = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.2)) { showWhy = true }
        try? await Task.sleep(for: .seconds(4.5))
        if !Task.isCancelled { onDone() }
    }
}
