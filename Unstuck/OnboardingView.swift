import SwiftUI

/// First-run intro. A few quiet breaths that say what this is — no tutorial, no
/// arrows, no pressure. Tap to move through; skip anytime. The rave waits to be found.
struct OnboardingView: View {
    let onDone: () -> Void

    @State private var step = 0
    @State private var lineIn = false

    // Declarative, warm — the app's voice. Never a command. Lines 3–4 added for a
    // wider audience: a plain privacy reassurance and a no-label note on how it
    // adapts (never names a state; just "meets you where you are").
    private let lines = [
        "this is a place to put\nwhat's in your head.",
        "type anything.\nit finds its own spot.",
        "what you write stays here,\non your phone. only yours.",
        "it quietly learns your rhythm,\nand meets you where you are.",
        "come and go as you like.\nnothing here is ever overdue.",
    ]

    var body: some View {
        ZStack {
            // Calm deep-space backdrop
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.13),
                         Color(red: 0.01, green: 0.01, blue: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // A single faint breathing node — a hint of the map to come
            Circle()
                .stroke(Color(red: 0.3, green: 0.85, blue: 0.75).opacity(0.3), lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .offset(y: -150)

            Text(lines[step])
                .font(.system(size: 20, weight: .light, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .padding(.horizontal, 44)
                .opacity(lineIn ? 1 : 0)
                .offset(y: lineIn ? 0 : 10)

            VStack {
                HStack {
                    Spacer()
                    Button(action: finish) {
                        Text("skip")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                    }
                }
                Spacer()
                // Progress dots + gentle prompt
                HStack(spacing: 6) {
                    ForEach(lines.indices, id: \.self) { i in
                        Circle()
                            .fill(.white.opacity(i == step ? 0.7 : 0.2))
                            .frame(width: 5, height: 5)
                    }
                }
                Text("tap to continue")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 14)
                    .padding(.bottom, 60)
            }
            .padding(.top, 50)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: advance)
        .onAppear { animateLineIn() }
    }

    private func animateLineIn() {
        lineIn = false
        withAnimation(.easeOut(duration: 0.6)) { lineIn = true }
    }

    private func advance() {
        HapticEngine.shared.tap()
        if step >= lines.count - 1 {
            finish()
        } else {
            withAnimation(.easeIn(duration: 0.25)) { lineIn = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                step += 1
                animateLineIn()
            }
        }
    }

    private func finish() {
        HapticEngine.shared.reward(.soft)
        onDone()
    }
}
