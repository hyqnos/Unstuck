// UnstuckWidget.swift
// The Live Activity: a focus-session pill on the Lock Screen and in the
// Dynamic Island. Shows the current brain-mode glyph, a self-running countdown,
// and whether focus music is on. No demands, no guilt — just ambient presence.
import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Small helpers

private extension Color {
    /// Build a Color from a "RRGGBB" hex string (falls back to teal).
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

@available(iOS 16.1, *)
private struct Countdown: View {
    let state: FocusSessionAttributes.ContentState
    var font: Font = .title2
    var body: some View {
        Group {
            if state.isPaused {
                Text(timeString(state.pausedRemaining))
            } else {
                // System-driven live countdown — updates without app pushes.
                Text(timerInterval: Date()...state.endDate, countsDown: true)
            }
        }
        .font(font.monospacedDigit())
        .fontWeight(.semibold)
    }
    private func timeString(_ t: TimeInterval) -> String {
        let s = max(0, Int(t)); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Lock Screen / banner view

@available(iOS 16.1, *)
struct FocusLockScreenView: View {
    let context: ActivityViewContext<FocusSessionAttributes>
    var body: some View {
        let accent = Color(hex: context.state.accentHex)
        HStack(spacing: 14) {
            Image(systemName: context.state.moodGlyph)
                .font(.title2)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.moodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Countdown(state: context.state)
                    .foregroundStyle(accent)
                if context.state.musicOn {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.55))
        .activitySystemActionForegroundColor(accent)
    }
}

// MARK: - Widget (Live Activity configuration + Dynamic Island)
// @main lives on UnstuckWidgetBundle (HomeWidget.swift), which lists both widgets.

@available(iOS 16.1, *)
struct UnstuckWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusSessionAttributes.self) { context in
            FocusLockScreenView(context: context)
        } dynamicIsland: { context in
            let accent = Color(hex: context.state.accentHex)
            return DynamicIsland {
                // Expanded (long-press) regions
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.moodLabel).font(.caption)
                    } icon: {
                        Image(systemName: context.state.moodGlyph)
                            .foregroundStyle(accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.musicOn {
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Countdown(state: context.state, font: .title)
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: context.state.moodGlyph)
                    .foregroundStyle(accent)
            } compactTrailing: {
                Countdown(state: context.state, font: .caption2)
                    .foregroundStyle(accent)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: context.state.moodGlyph)
                    .foregroundStyle(accent)
            }
            .widgetURL(URL(string: "unstuck://focus"))
            .keylineTint(accent)
        }
    }
}
