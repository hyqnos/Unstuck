import SwiftUI

struct QuickCaptureBar: View {
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField("thought...", text: $text)
                .font(.system(.callout, design: .monospaced))   // scales with Dynamic Type
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($focused)
                .onSubmit(submit)

            if !text.isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .panel(RoundedRectangle(cornerRadius: 18, style: .continuous), highlighted: focused)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        text = ""
        // Keep focus so a rapid brain-dump keeps flowing — tap away to dismiss
    }
}
