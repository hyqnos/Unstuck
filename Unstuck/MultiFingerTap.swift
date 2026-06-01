import SwiftUI
import UIKit

/// Detects an N-finger tap (SwiftUI can't count fingers).
/// Attaches its recognizer to the HOST view's superview and recognizes
/// simultaneously with everything else — so it never blocks pan/pinch/tap.
struct MultiFingerTap: UIViewRepresentable {
    let touches: Int
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let v = AttachView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false   // pure observer — passes touches through
        v.onAttach = { host in
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.fired))
            tap.numberOfTouchesRequired = touches
            tap.delegate = context.coordinator
            tap.cancelsTouchesInView = false
            host.addGestureRecognizer(tap)
        }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(action) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }

        @objc func fired() { action() }

        // Let it coexist with SwiftUI's pan/pinch/rotate/tap recognizers
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    /// Invisible view that adds the recognizer to its superview once attached.
    final class AttachView: UIView {
        var onAttach: ((UIView) -> Void)?
        private var done = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard !done, let host = superview else { return }
            done = true
            onAttach?(host)
        }
    }
}
