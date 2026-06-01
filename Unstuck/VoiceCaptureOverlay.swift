import SwiftUI

struct VoiceCaptureOverlay: View {
    var voice: VoiceCapture
    let onDone: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Dim the map behind
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { cancel() }

            VStack(spacing: 28) {
                ListeningOrb(active: isListening)

                // Live transcription
                VStack(spacing: 8) {
                    if !voice.liveText.isEmpty {
                        Text(voice.liveText)
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .padding(.horizontal, 32)
                            .transition(.opacity)
                    } else if isListening {
                        Text("listening...")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    if case .error(let msg) = voice.state {
                        Text(msg)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: voice.liveText)

                // Cancel
                Button(action: cancel) {
                    Text("cancel")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .onChange(of: voice.state) { _, newState in
            if case .done(let text) = newState {
                HapticEngine.shared.complete()
                onDone(text)
            }
        }
    }

    private var isListening: Bool {
        if case .listening = voice.state { return true }
        if case .processing = voice.state { return true }
        return false
    }

    private func cancel() {
        voice.reset()
        HapticEngine.shared.tap()
        onCancel()
    }
}

// MARK: - Listening orb — breathing core + concentric sonar rings

private struct ListeningOrb: View {
    let active: Bool

    private let teal = Color(red: 0.3, green: 0.85, blue: 0.75)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                // Three sonar rings, each offset in phase, expanding + fading outward
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.6 + Double(i) * 0.66).truncatingRemainder(dividingBy: 2) / 2
                    Circle()
                        .stroke(teal.opacity((1 - phase) * 0.5), lineWidth: 1.5)
                        .frame(width: 80 + phase * 150, height: 80 + phase * 150)
                }

                // Soft glow halo, gently breathing
                let breathe = sin(t * 1.8) * 0.5 + 0.5
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [teal.opacity(0.35), .clear],
                            center: .center, startRadius: 4, endRadius: 70
                        )
                    )
                    .frame(width: 150, height: 150)
                    .scaleEffect(0.9 + breathe * 0.18)
                    .opacity(0.6 + breathe * 0.4)

                // Core
                Circle()
                    .fill(teal.opacity(0.18))
                    .frame(width: 80, height: 80)
                    .overlay(Circle().stroke(teal.opacity(0.7), lineWidth: 1))

                Image(systemName: active ? "waveform" : "mic")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .scaleEffect(0.95 + breathe * 0.12)
            }
            .frame(width: 240, height: 240)
        }
        .frame(width: 240, height: 240)
    }
}
