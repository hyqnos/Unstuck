import SwiftUI
import SwiftData

/// Shown on return after a freeze. The most important screen in the app.
///
/// Rules (hard constraints):
///  - NO "welcome back", no "you've been gone", no acknowledging absence.
///  - Warm, interesting, zero-pressure. Each crumb gives a little dopamine.
///  - Every crumb has a "not yet" exit. Nothing is ever demanded.
///  - Emotional floor is "you're fine."
struct BreadcrumbOverlay: View {
    let ownWords: [BrainItem]        // the user's own recent captures
    let easyWin: BrainItem?          // one tiny, climbable thing
    let coachingNote: CoachingNote?  // their own insight from a good day

    let onPickItem: (BrainItem) -> Void   // enter survival mode on this one
    let onEnterMap: () -> Void            // quietly slip into the full map

    @State private var step = 0
    @State private var appeared = false

    // The crumb trail, built from what's available
    private var crumbs: [Crumb] {
        var list: [Crumb] = []

        // 1. A warm, declarative opener — never a question, never a demand
        list.append(.message("the map is still here.\nnothing moved without you."))

        // 2. Their own words reflected back
        if let recent = ownWords.first {
            list.append(.ownWord(recent))
        }

        // 3. Their own insight, in their own voice
        if let note = coachingNote {
            list.append(.coaching(note))
        }

        // 4. One easy win — glowing, low pressure
        if let win = easyWin {
            list.append(.easyWin(win))
        }

        // 5. Quiet close
        list.append(.message("that's enough.\npull the map in when you want it."))
        return list
    }

    var body: some View {
        ZStack {
            // Deep calm backdrop — survival darkness
            Color(red: 0.02, green: 0.02, blue: 0.06).ignoresSafeArea()

            // Single faint breathing constellation — the only motion
            ConstellationPulse()
                .opacity(0.5)

            VStack {
                Spacer()

                if step < crumbs.count {
                    crumbView(crumbs[step])
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92)),
                            removal: .opacity
                        ))
                }

                Spacer()

                // Always-present quiet exit — the "not yet" / "out" door
                Button(action: advanceOrExit) {
                    Text(step >= crumbs.count - 1 ? "open the map" : "not yet")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .panel(Capsule())
                }
                .padding(.bottom, 50)
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 1.2)) { appeared = true }
            HapticEngine.shared.settle()
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: step)
    }

    // MARK: - Crumb rendering

    @ViewBuilder
    private func crumbView(_ crumb: Crumb) -> some View {
        switch crumb {
        case .message(let text):
            Text(text)
                .font(.system(size: 18, weight: .light, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, 40)

        case .ownWord(let item):
            VStack(spacing: 16) {
                Text("you left this")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Text("\u{201C}\(item.text)\u{201D}")
                    .font(.system(size: 20, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 36)
            }

        case .coaching(let note):
            VStack(spacing: 16) {
                Text("you told yourself, once")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Text("\u{201C}\(note.text)\u{201D}")
                    .font(.system(size: 19, weight: .light, design: .monospaced))
                    .foregroundStyle(Color(red: 0.7, green: 0.85, blue: 1.0).opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 36)
            }

        case .easyWin(let item):
            VStack(spacing: 20) {
                Text("if you want one thing")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))

                Button {
                    HapticEngine.shared.reward(.medium)
                    onPickItem(item)
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(item.text)
                            .font(.system(size: 17, weight: .light, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                        if let mins = item.estimatedMinutes {
                            Text("\(mins) min")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 24)
                    .panel(RoundedRectangle(cornerRadius: 20, style: .continuous),
                           tint: .white.opacity(0.08))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Flow

    private func advanceOrExit() {
        HapticEngine.shared.tap()
        if step >= crumbs.count - 1 {
            onEnterMap()
        } else {
            step += 1
        }
    }

    // MARK: - Crumb type

    private enum Crumb {
        case message(String)
        case ownWord(BrainItem)
        case coaching(CoachingNote)
        case easyWin(BrainItem)
    }
}

// MARK: - Breathing constellation

private struct ConstellationPulse: View {
    @State private var phase = false

    private let points: [(CGFloat, CGFloat)] = [
        (0.3, 0.25), (0.55, 0.18), (0.7, 0.35),
        (0.45, 0.4), (0.25, 0.55), (0.6, 0.6),
        (0.75, 0.7), (0.4, 0.72), (0.5, 0.5),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Connecting lines
                Path { path in
                    for i in 0..<points.count - 1 {
                        let a = CGPoint(x: points[i].0 * geo.size.width,
                                        y: points[i].1 * geo.size.height)
                        let b = CGPoint(x: points[i + 1].0 * geo.size.width,
                                        y: points[i + 1].1 * geo.size.height)
                        path.move(to: a)
                        path.addLine(to: b)
                    }
                }
                .stroke(.white.opacity(phase ? 0.12 : 0.05), lineWidth: 0.6)

                ForEach(points.indices, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(phase ? 0.6 : 0.25))
                        .frame(width: 4, height: 4)
                        .position(x: points[i].0 * geo.size.width,
                                  y: points[i].1 * geo.size.height)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}
