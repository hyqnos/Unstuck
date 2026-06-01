import SwiftUI

/// Frosted-panel look that replaces Liquid Glass.
/// Pure translucent fill + gradient edge — NO backdrop sampling, so it costs
/// nothing to re-composite under 3D transforms. Reads as frosted over the dark sky.
struct PanelStyle<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var highlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.white.opacity(highlighted ? 0.10 : 0.055))
                    .overlay(
                        // Top-down sheen for a hint of dimensionality
                        shape.fill(
                            LinearGradient(
                                colors: [.white.opacity(0.06), .white.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    )
                    .overlay(
                        // Optional mood/selection tint
                        tint.map { shape.fill($0) }
                    )
            }
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(highlighted ? 0.5 : 0.22),
                            .white.opacity(0.06),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
    }
}

extension View {
    /// Frosted panel with any shape (RoundedRectangle, Capsule, Circle…).
    func panel<S: Shape>(_ shape: S, tint: Color? = nil, highlighted: Bool = false) -> some View {
        modifier(PanelStyle(shape: shape, tint: tint, highlighted: highlighted))
    }
}
