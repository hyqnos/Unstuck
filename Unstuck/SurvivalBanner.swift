import SwiftUI

/// Survival map mode: everything dims, one item glows.
/// The emotional floor — when choosing is too much, the app holds up a single thing.
/// Always a "not yet" exit (release). Never a demand.
struct SurvivalBanner: View {
    let item: BrainItem
    let onDone: () -> Void
    let onRelease: () -> Void

    @State private var glow = false
    @State private var pressing = false

    var body: some View {
        ZStack {
            // Dim the whole map behind
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { } // absorb taps

            VStack(spacing: 28) {
                Spacer()

                Text("just this one")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))

                // The single glowing thing
                VStack(spacing: 14) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.7))
                        .scaleEffect(glow ? 1.1 : 0.95)

                    Text(item.text)
                        .font(.system(size: 20, weight: .light, design: .monospaced))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)

                    if let mins = item.estimatedMinutes {
                        Text("\(mins) min")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
                .panel(RoundedRectangle(cornerRadius: 24, style: .continuous),
                       tint: .white.opacity(0.1))
                .shadow(color: .white.opacity(glow ? 0.18 : 0.06), radius: glow ? 30 : 14)

                Spacer()

                // Done — long-press so it's never an accidental demand
                Text(pressing ? "almost…" : "hold when it's done")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(pressing ? 0.9 : 0.5))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .panel(Capsule(), tint: pressing ? .white.opacity(0.18) : nil, highlighted: pressing)
                    .scaleEffect(pressing ? 1.06 : 1.0)
                    .onLongPressGesture(minimumDuration: 0.5, pressing: { p in
                        withAnimation(.easeOut(duration: 0.2)) { pressing = p }
                        if p { HapticEngine.shared.tap() }
                    }, perform: onDone)

                // Not yet — always there
                Button(action: onRelease) {
                    Text("not yet")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}
