import SwiftUI

/// Ambient companion — a small living presence in the corner. It breathes, blinks,
/// glances around at organic intervals, and reacts to what you do (perks up on a
/// win, droops/softens when you're low). Presence, not words — which also sidesteps
/// demand-avoidance: it never asks for anything.
///
/// Built natively in SwiftUI (no Live2D, no dependency). The *character* is meant to
/// be swappable: today it's an expressive orb-creature; a rigged 3D model
/// (a USDZ lion / monkey / etc.) can drop into `creature` later behind a
/// RealityKit/SceneKit view without touching the behaviour below.
struct CompanionView: View {
    private let mood = MoodDetector.shared
    private let settings = AppSettings.shared

    @State private var breathe = false
    @State private var blink = false
    @State private var gaze: CGSize = .zero     // where the eyes are looking
    @State private var bob: CGFloat = 0          // idle float
    @State private var hop: CGFloat = 0          // celebrate jump
    @State private var sparkle = false
    @State private var born = false

    private var tint: Color {
        switch mood.mode {
        case .ready:      return Color(red: 0.30, green: 0.85, blue: 0.60)
        case .hyperfocus: return Color(red: 0.45, green: 0.50, blue: 1.00)
        case .lowBattery: return Color(red: 1.00, green: 0.60, blue: 0.40)
        case .overwhelm:  return Color(red: 0.60, green: 0.66, blue: 0.78)
        }
    }
    private var lowEnergy: Bool { mood.mode == .overwhelm || mood.mode == .lowBattery }
    private var calm: Bool { settings.calmMode }

    var body: some View {
        creature
            .frame(width: 58, height: 58)
            .scaleEffect(breathe ? 1.04 : 1.0)        // breathing
            .offset(y: bob - hop)
            .scaleEffect(born ? 1 : 0.2)              // birth pop-in
            .opacity(born ? 1 : 0)
            .contentShape(Circle())
            .onTapGesture { poke() }
            .task { await live() }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { born = true }
                withAnimation(.easeInOut(duration: lowEnergy ? 5 : 3).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .taskCompleted)) { _ in celebrate() }
            .animation(.easeInOut(duration: 1.2), value: tint)   // recolour gently when mood shifts
    }

    // MARK: - The creature (swap this for a 3D model later)

    private var creature: some View {
        ZStack {
            Circle().fill(tint.opacity(0.25)).blur(radius: 12).scaleEffect(1.3)   // aura
            Capsule()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.7)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: tint.opacity(0.5), radius: 8)

            HStack(spacing: 9) { eye; eye }
                .offset(y: -2)

            if sparkle {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .offset(y: -34)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // a subtle 3D turn toward whatever it's looking at
        .rotation3DEffect(.degrees(Double(gaze.width) * 1.4), axis: (x: 0, y: 1, z: 0))
    }

    private var eye: some View {
        ZStack {
            Capsule().fill(.white)
                .frame(width: 11, height: blink ? 2 : 13)
            if !blink {
                Circle().fill(.black.opacity(0.82))
                    .frame(width: 5, height: 5)
                    .offset(x: gaze.width, y: gaze.height + (lowEnergy ? 2 : 0))   // droop when tired
            }
        }
        .frame(width: 11, height: 13)
    }

    // MARK: - Life loop (organic random timing)

    @MainActor private func live() async {
        withAnimation(.easeInOut(duration: lowEnergy ? 4 : 2.4).repeatForever(autoreverses: true)) {
            bob = lowEnergy ? 1.5 : 3
        }
        while !Task.isCancelled {
            let wait = lowEnergy ? Double.random(in: 4...8) : Double.random(in: 2.2...5.5)
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { break }
            await blinkOnce()
            if mood.mode != .hyperfocus, Bool.random() { await glance() }   // hyperfocus stares ahead
        }
    }

    @MainActor private func blinkOnce() async {
        withAnimation(.easeInOut(duration: 0.08)) { blink = true }
        try? await Task.sleep(for: .seconds(0.12))
        withAnimation(.easeInOut(duration: 0.10)) { blink = false }
        if Bool.random() {                                   // occasional double-blink — very human
            try? await Task.sleep(for: .seconds(0.14))
            withAnimation(.easeInOut(duration: 0.08)) { blink = true }
            try? await Task.sleep(for: .seconds(0.10))
            withAnimation(.easeInOut(duration: 0.10)) { blink = false }
        }
    }

    @MainActor private func glance() async {
        let dir = CGSize(width: .random(in: -3...3), height: .random(in: -2...2))
        withAnimation(.easeOut(duration: 0.3)) { gaze = dir }
        try? await Task.sleep(for: .seconds(Double.random(in: 0.8...2.0)))
        withAnimation(.easeOut(duration: 0.4)) { gaze = .zero }
    }

    private func poke() {
        HapticEngine.shared.tap()
        Task { @MainActor in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { hop = 8 }
            try? await Task.sleep(for: .seconds(0.18))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { hop = 0 }
            await glance()
        }
    }

    private func celebrate() {
        guard !calm else { return }
        HapticEngine.shared.reward(.light)
        Task { @MainActor in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { hop = 16; sparkle = true }
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { hop = 0 }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.easeOut(duration: 0.3)) { sparkle = false }
        }
    }
}
