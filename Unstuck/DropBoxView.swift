import SwiftUI

// MARK: - Tier

enum DropTier {
    case common, rare, epic, mythic, legendary, chaos

    var color: Color {
        switch self {
        case .common:    return Color(white: 0.9)
        case .rare:      return Color(red: 0.35, green: 0.55, blue: 1.0)
        case .epic:      return Color(red: 0.75, green: 0.25, blue: 1.0)
        case .mythic:    return Color(red: 1.0,  green: 0.45, blue: 0.1)
        case .legendary: return Color(red: 1.0,  green: 0.82, blue: 0.1)
        case .chaos:     return Color(red: 1.0,  green: 0.08, blue: 0.35)
        }
    }

    var particleCount: Int {
        switch self {
        case .common:    return 18
        case .rare:      return 26
        case .epic:      return 34
        case .mythic:    return 44
        case .legendary: return 56
        case .chaos:     return 80
        }
    }

    var spinSpeed: Double {
        switch self {
        case .chaos: return 3.0
        default:     return 1.0
        }
    }

    static func tier(for zone: ZoneType) -> DropTier {
        switch zone {
        case .captures:       return .common
        case .reminders:      return .rare
        case .timeManagement: return .rare
        case .routines:       return .epic
        case .health:         return .epic
        case .ideas:          return .mythic
        case .someday:        return .legendary
        }
    }
}

// MARK: - Particle

private struct Particle {
    let angle:    Double
    let speed:    Double
    let size:     CGFloat
    let wobble:   Double   // slight angle drift for chaos
}

// MARK: - Drop Box

struct DropBoxView: View {
    let tier: DropTier
    let onBurst: () -> Void

    @State private var appeared    = false
    @State private var spinning    = false
    @State private var glowPulse   = false
    @State private var burst       = false
    @State private var burstStart  = Date()
    @State private var jitter      = CGSize.zero
    @State private var scale       = CGFloat(0.0)

    private let particles: [Particle] = {
        (0..<80).map { i in
            Particle(
                angle:  Double(i) / 80.0 * .pi * 2 + Double.random(in: -0.2...0.2),
                speed:  Double.random(in: 0.5...1.6),
                size:   CGFloat.random(in: 3...10),
                wobble: Double.random(in: -0.3...0.3)
            )
        }
    }()

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            // Burst particles
            if burst {
                ParticleCanvas(tier: tier, particles: Array(particles.prefix(tier.particleCount)),
                               startDate: burstStart)
                    .frame(width: 400, height: 400)
            }

            if !burst {
                VStack(spacing: 0) {
                    // Glow beam shooting upward
                    LinearGradient(
                        colors: [tier.color.opacity(0), tier.color.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: 4, height: 160)
                    .blur(radius: 6)
                    .scaleEffect(x: glowPulse ? 3.5 : 1.5, y: 1.0, anchor: .bottom)
                    .opacity(glowPulse ? 0.9 : 0.4)

                    // The box
                    ZStack {
                        // Outer glow
                        RoundedRectangle(cornerRadius: 20)
                            .fill(tier.color.opacity(0.15))
                            .frame(width: 110, height: 110)
                            .blur(radius: glowPulse ? 22 : 12)
                            .scaleEffect(glowPulse ? 1.4 : 1.0)

                        // Box body
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [tier.color.opacity(0.3), tier.color.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 90, height: 90)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(tier.color.opacity(0.8), lineWidth: 1.5)
                            )

                        // Star
                        Image(systemName: tier == .chaos ? "staroflife.fill" : "star.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(tier.color)
                            .shadow(color: tier.color.opacity(0.8), radius: 12)
                            .scaleEffect(glowPulse ? 1.15 : 0.95)
                    }
                    .rotationEffect(.degrees(spinning ? 360 * tier.spinSpeed : 0))
                    .animation(
                        .linear(duration: 1.2 / tier.spinSpeed).repeatForever(autoreverses: false),
                        value: spinning
                    )
                }
                .scaleEffect(scale)
                .offset(jitter)
            }
        }
        .onAppear(perform: startSequence)
    }

    // MARK: - Sequence

    private func startSequence() {
        // 1. Box springs in
        withAnimation(.spring(response: 0.38, dampingFraction: 0.6)) {
            appeared = true
            scale    = 1.0
        }
        spinning = true

        // 2. Glow pulse
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            glowPulse = true
        }

        // Chaos shake
        if tier == .chaos { startShaking() }

        // 3. Haptic build-up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            HapticEngine.shared.tap()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            HapticEngine.shared.reward(.light)
        }

        // 4. BURST
        let burstDelay = tier == .chaos ? 0.65 : 0.85
        DispatchQueue.main.asyncAfter(deadline: .now() + burstDelay) {
            burstStart = Date()

            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                scale = 1.35
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                // Mega haptic on burst
                HapticEngine.shared.fling(rotationRate: tier == .chaos ? 8 : 4)
                withAnimation(.easeOut(duration: 0.15)) { scale = 0 }
                burst = true
                onBurst()
            }
        }
    }

    private func startShaking() {
        func doShake(count: Int) {
            guard count > 0 && !burst else { return }
            let amp: CGFloat = 6
            withAnimation(.easeInOut(duration: 0.06)) {
                jitter = CGSize(
                    width:  CGFloat.random(in: -amp...amp),
                    height: CGFloat.random(in: -amp...amp)
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                doShake(count: count - 1)
            }
        }
        doShake(count: 20)
    }
}

// MARK: - Particle Canvas

private struct ParticleCanvas: View {
    let tier:      DropTier
    let particles: [Particle]
    let startDate: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/120)) { tl in
            Canvas { ctx, size in
                let elapsed = tl.date.timeIntervalSince(startDate)
                let t = min(1.0, elapsed / 0.7)
                guard t > 0 else { return }

                let cx = size.width  / 2
                let cy = size.height / 2

                for p in particles {
                    let angle = p.angle + p.wobble * t
                    let dist  = p.speed * t * 180
                    let x     = cx + CGFloat(cos(angle)) * dist
                    let y     = cy + CGFloat(sin(angle)) * dist

                    // Fade out in last 30% of animation
                    let opacity = t < 0.7 ? 1.0 : 1.0 - (t - 0.7) / 0.3
                    let pSize   = p.size * CGFloat(1 - t * 0.4)

                    let rect = CGRect(x: x - pSize/2, y: y - pSize/2,
                                      width: pSize, height: pSize)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .color(tier.color.opacity(opacity))
                    )

                    // Trailing glow dot
                    let glowRect = CGRect(x: x - pSize, y: y - pSize,
                                         width: pSize * 2, height: pSize * 2)
                    ctx.fill(
                        Path(ellipseIn: glowRect),
                        with: .color(tier.color.opacity(opacity * 0.25))
                    )
                }

                // Center flash
                let flashOpacity = t < 0.15 ? t / 0.15 : max(0, 1 - (t - 0.15) / 0.3)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - 60, y: cy - 60, width: 120, height: 120)),
                    with: .color(.white.opacity(flashOpacity * 0.85))
                )
            }
        }
    }
}
