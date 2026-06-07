import SwiftUI

/// The brain-dump valve. A calm, full-screen pad where you stream everything at once —
/// thoughts, tasks, ideas — no structure required. Each line you add quietly loads a dot
/// (the "ammo"); "let it go" hands the whole stream to the funnel, which sorts every item
/// and fires them onto the board. Zero pressure, never a demand to organise (PDA-safe).
struct BrainDumpView: View {
    @Binding var isPresented: Bool
    let onDump: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    private let teal = Color(red: 0.3, green: 0.85, blue: 0.75)

    private var items: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
                .onTapGesture { focused = false }

            VStack(spacing: 14) {
                VStack(spacing: 3) {
                    Text("empty your head")
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("one thing a line, or just ramble. i'll sort it.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }

                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .tint(teal)
                    .focused($focused)
                    .frame(maxHeight: 300)
                    .padding(12)
                    .panel(RoundedRectangle(cornerRadius: 18, style: .continuous), highlighted: focused)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("brush teeth\nthat email to sam\nbook idea: a calm map\n…")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.18))
                                .padding(.horizontal, 18).padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }

                // The loaded pile — a dot per item (you see the ammo load).
                HStack(spacing: 5) {
                    ForEach(0..<min(items.count, 28), id: \.self) { _ in
                        Circle().fill(teal.opacity(0.85)).frame(width: 6, height: 6)
                    }
                }
                .frame(height: 8)
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: items.count)

                HStack {
                    Button("not now") { close() }
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Button(action: fire) {
                        Text(items.count > 1 ? "let it all go · \(items.count)" : "let it go")
                            .font(.system(.callout, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(teal, in: Capsule())
                            .shadow(color: teal.opacity(0.5), radius: items.isEmpty ? 0 : 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(items.isEmpty)
                    .opacity(items.isEmpty ? 0.35 : 1)
                    .accessibilityLabel("Let it all go — \(items.count) items")
                }
            }
            .padding(22)
            .padding(.top, 30)
        }
        .transition(.opacity)
        .onAppear { focused = true }
    }

    private func fire() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        HapticEngine.shared.reward(.medium)
        onDump(t)
        close()
    }

    private func close() {
        focused = false
        withAnimation(.easeOut(duration: 0.25)) { isPresented = false }
    }
}
