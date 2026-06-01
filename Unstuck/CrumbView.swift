import SwiftUI

struct CrumbView: View {
    let crumb: KnowledgeCrumb

    @State private var expanded = false
    @State private var appeared = false
    @State private var dismissed = false
    @State private var dragOffset: CGSize = .zero
    @State private var flyOffset: CGSize = .zero
    @State private var flyScale: CGFloat = 1.0
    @State private var flyOpacity: Double = 1.0

    private var isFact: Bool { crumb.type == .brainFact }
    private let dismissSpeed: CGFloat = 280   // min velocity to trigger dismiss

    var body: some View {
        if !dismissed {
            content
                .offset(x: dragOffset.width + flyOffset.width,
                        y: dragOffset.height + flyOffset.height)
                .scaleEffect(flyScale * (appeared ? 1.0 : 0.5))
                .opacity(flyOpacity * (appeared ? 1.0 : 0))
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)
                        .delay(Double.random(in: 0.1...0.8))) {
                        appeared = true
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { v in
                            withAnimation(.interactiveSpring()) {
                                dragOffset = v.translation
                            }
                        }
                        .onEnded { v in
                            let speed = sqrt(
                                v.velocity.width  * v.velocity.width +
                                v.velocity.height * v.velocity.height
                            )

                            if speed > dismissSpeed {
                                fling(velocity: v.velocity)
                            } else {
                                // Too slow — snap back
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    dragOffset = .zero
                                }
                                HapticEngine.shared.tap()
                            }
                        }
                )
                .onTapGesture {
                    guard dragOffset == .zero else { return }
                    HapticEngine.shared.tap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        expanded.toggle()
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: expanded)
        }
    }

    // MARK: - Crumb content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                Text(crumb.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 200, alignment: .leading)
                    .padding(.bottom, 8)

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            expanded = false
                        }
                    } label: {
                        Text("got it")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Text("↑ flick to dismiss")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                }
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(isFact
                              ? Color.white.opacity(0.5)
                              : Color(red: 0.3, green: 0.85, blue: 0.75).opacity(0.7))
                        .frame(width: 5, height: 5)
                    Text(crumb.text.prefix(28) + "…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, expanded ? 14 : 10)
        .padding(.vertical, expanded ? 10 : 6)
        .panel(
            RoundedRectangle(cornerRadius: expanded ? 14 : 20, style: .continuous),
            tint: isFact ? nil : Color(red: 0.3, green: 0.85, blue: 0.75).opacity(0.12)
        )
        // Tilt slightly while dragging
        .rotationEffect(.degrees(Double(dragOffset.width / 12).clamped(to: -15...15)))
    }

    // MARK: - Fling physics

    private func fling(velocity: CGSize) {
        // Read gyro at the exact moment of release — wrist snap drives the haptic
        let gyro = MotionAdaptor.shared.rotationRate
        HapticEngine.shared.fling(rotationRate: gyro)
        SpatialAudioService.shared.playBlip(.dismiss, atX: crumb.positionX, y: crumb.positionY)

        // Throw distance scales with wrist snap intensity — harder snap = farther fling
        let throwDistance: CGFloat = 280 + CGFloat(gyro.clamped(to: 0...6)) * 25

        let norm = sqrt(velocity.width * velocity.width + velocity.height * velocity.height)
        let ux = velocity.width  / norm
        let uy = velocity.height / norm

        withAnimation(.easeOut(duration: 0.32)) {
            flyOffset  = CGSize(width: ux * throwDistance, height: uy * throwDistance)
            flyScale   = 0.3
            flyOpacity = 0
        }

        // Echo haptic as it disappears — soft finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            HapticEngine.shared.settle()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            dismissed = true
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
