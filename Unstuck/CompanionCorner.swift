import SwiftUI

/// Wraps the corner companion (3D creature, or the 2D fallback under Reduce Motion)
/// and gives it the occasional **ambient mutter** — a tiny declarative thought
/// bubble that drifts up now and then. Presence, never instructions: it muses, it
/// never tells you to do anything (PDA-safe), and at worst it says "you're fine"
/// (RSD-safe). Quiet during hyperfocus, rarer in calm mode, and tap to dismiss.
struct CompanionCorner: View {
    let use3D: Bool
    private let mood = MoodDetector.shared
    private let settings = AppSettings.shared
    @State private var mutter: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            if let m = mutter {
                Text(m)
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .panel(Capsule())
                    .fixedSize()
                    .offset(y: -80)
                    .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                    .onTapGesture { withAnimation(.easeOut(duration: 0.3)) { mutter = nil } }
                    .zIndex(1)
            }
            Group {
                if use3D { Companion3D() } else { CompanionView() }
            }
        }
        .task { await museLoop() }
        .onReceive(NotificationCenter.default.publisher(for: .taskCompleted)) { _ in
            if !settings.calmMode, Bool.random() { say(Self.wins.randomElement() ?? "nice one.", for: 3) }
        }
    }

    @MainActor private func museLoop() async {
        while !Task.isCancelled {
            let gap = settings.calmMode ? Double.random(in: 90...160) : Double.random(in: 45...95)
            try? await Task.sleep(for: .seconds(gap))
            if Task.isCancelled { break }
            guard mood.mode != .hyperfocus, mutter == nil else { continue }   // stay quiet in flow
            say(line(for: mood.mode), for: 4)
        }
    }

    @MainActor private func say(_ text: String, for seconds: Double) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { mutter = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation(.easeOut(duration: 0.4)) { if mutter == text { mutter = nil } }
        }
    }

    private func line(for mode: BrainMode) -> String {
        let pool: [String]
        switch mode {
        case .ready:      pool = Self.ready + Self.general
        case .lowBattery: pool = Self.low + Self.general
        case .overwhelm:  pool = Self.overwhelm
        case .hyperfocus: pool = Self.general
        }
        return pool.randomElement() ?? "no rush."
    }

    // Declarative, gentle — never a command. The app's voice.
    static let general   = ["the map's still here.", "no rush.", "thoughts float. that's fine.",
                            "you can just look.", "nice and quiet.", "i'm around."]
    static let ready     = ["we're moving.", "feels good, huh.", "nice momentum."]
    static let low       = ["rest counts too.", "slow is okay.", "easy does it."]
    static let overwhelm = ["one thing. or none.", "breathe — i'm here.", "you're fine.", "smaller is allowed."]
    static let wins      = ["oh nice.", "that's a win.", "saw that.", "nice one."]
}
