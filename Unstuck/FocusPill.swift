import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&v), s.count == 6 else {
            self = Color(red: 0.3, green: 0.85, blue: 0.75); return
        }
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

struct FocusPill: View {
    var session: FocusSessionController
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                let visuals = LiveActivityService.visuals(for: MoodDetector.shared.mode)
                Image(systemName: visuals.glyph)
                    .foregroundStyle(Color(hex: visuals.hex))
                    .font(.system(size: 18))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(visuals.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                Spacer()
                
                // Countdown
                let s = max(0, Int(session.remaining))
                Text(String(format: "%d:%02d", s / 60, s % 60))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: visuals.hex))
                    .contentTransition(.numericText())
                
                // Pause/Resume/Stop
                Button(action: {
                    HapticEngine.shared.tap()
                    if session.isPaused { session.resume() } else { session.pause() }
                }) {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .panel(Circle(), tint: .white.opacity(0.1))
                }
                
                Button(action: {
                    HapticEngine.shared.tap()
                    withAnimation { session.end() }
                }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .panel(Circle(), tint: .white.opacity(0.1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .panel(Capsule(), tint: Color.black.opacity(0.85))
            .padding(.horizontal, 20)
            Spacer()
        }
        .padding(.top, 60)
    }
}
