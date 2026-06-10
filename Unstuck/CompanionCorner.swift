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
    @State private var showPicker = false
    @State private var bodyDoubleTaste = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            // Character picker — long-press the companion to swap who's hanging out
            if showPicker {
                characterPicker
                    .offset(y: -88)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }

            companionBody
                // Tap = a taste of body-double mode: it steps forward, grows, and offers
                // company, then settles back. Presence, never a demand (PDA-safe). The full
                // "focus together" space is a later build — this is just the hint.
                .scaleEffect(bodyDoubleTaste ? (reduceMotion ? 1.25 : 1.9) : 1.0, anchor: .bottomTrailing)
                .offset(y: bodyDoubleTaste && !reduceMotion ? -36 : 0)
                .shadow(color: Color(red: 0.3, green: 0.85, blue: 0.75).opacity(bodyDoubleTaste ? 0.45 : 0),
                        radius: bodyDoubleTaste ? 22 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: bodyDoubleTaste)
                .contentShape(Rectangle())   // hit area over the transparent 3D view
                .onTapGesture { tasteBodyDouble() }
                .onLongPressGesture(minimumDuration: 0.4) {
                    HapticEngine.shared.reward(.soft)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showPicker.toggle() }
                }
                .accessibilityHint("Tap for a moment of company; press and hold to change companion")
        }
        .task { await museLoop() }
        .onReceive(NotificationCenter.default.publisher(for: .taskCompleted)) { _ in
            if !settings.calmMode, Bool.random() { say(Self.wins.randomElement() ?? "nice one.", for: 3) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .brainDumped)) { _ in
            if !settings.calmMode { say(Self.wins.randomElement() ?? "nice one.", for: 3) }   // a dump always earns a word
        }
    }

    @ViewBuilder private var companionBody: some View {
        if !use3D || settings.companionCharacter == .orb {
            CompanionView()                                       // 2D (also Reduce-Motion path)
        } else if settings.companionCharacter == .live2d {
            Live2DCompanion()                                     // Live2D slot (placeholder until a model)
        } else {
            Companion3D(character: settings.companionCharacter)   // native lion / fox / bear
                .id(settings.companionCharacter)   // rebuild the SceneKit scene when the species changes
        }
    }

    private var characterPicker: some View {
        HStack(spacing: 6) {
            ForEach(CompanionCharacter.allCases, id: \.self) { ch in
                Button {
                    HapticEngine.shared.tap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        settings.companionCharacter = ch
                        showPicker = false
                    }
                } label: {
                    Text(ch.label)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(settings.companionCharacter == ch ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .panel(Capsule(), tint: settings.companionCharacter == ch ? .white.opacity(0.15) : nil)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Companion: \(ch.label)")
            }
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

    /// A taste of body-double mode: the companion steps forward, grows, offers company,
    /// then settles back on its own. Invitation, never a demand. The full focus space is later.
    @MainActor private func tasteBodyDouble() {
        guard !bodyDoubleTaste else { return }
        HapticEngine.shared.reward(.soft)
        bodyDoubleTaste = true   // animated by the .animation(value:) modifier above
        say(Self.company.randomElement() ?? "want company?", for: 3)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            bodyDoubleTaste = false
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
    // Body-double taste — invitations to co-presence, never commands (PDA-safe).
    static let company   = ["want company?", "i'll sit with you.", "here with you.", "let's just be here."]
}
