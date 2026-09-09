#if os(iOS)
import SwiftUI
import UIKit

/// Puts the keyboard away on a tap that lands anywhere that isn't text.
///
/// The obvious SwiftUI answer — a `TapGesture` on the screen, or on a clear
/// background behind it — doesn't work here. The sections being typed into are
/// `List` rows, so a gesture on the list competes with the rows for the same
/// touch and a gesture on a background sits under a scroll view that swallows
/// it first. Either way the fields stop taking taps, which is a far worse bug
/// than the one being fixed.
///
/// So the recognizer goes on the window instead, with `cancelsTouchesInView`
/// off: it only ever *observes* the touch, and the row, button or toggle under
/// the finger still receives it exactly as before. The hit test is what makes
/// it safe to be that broad — a tap that lands in a field is a caret move, so
/// moving from one section to another keeps the keyboard up, and only a tap on
/// something that isn't text closes it.
struct KeyboardDismissTap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WindowAwareView {
        let view = WindowAwareView()
        // Zero-size and inert: this exists to find the window, not to be part
        // of the layout or to take a touch of its own.
        view.isUserInteractionEnabled = false
        view.onWindow = { [coordinator = context.coordinator] window in
            coordinator.attach(to: window)
        }
        return view
    }

    func updateUIView(_ view: WindowAwareView, context: Context) {}

    static func dismantleUIView(_ view: WindowAwareView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// A view with no appearance, there only to report the window it lands in —
    /// `window` is still nil while `makeUIView` runs, so the attach has to wait
    /// for the move rather than happen on creation.
    final class WindowAwareView: UIView {
        var onWindow: ((UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var recognizer: UITapGestureRecognizer?
        private weak var window: UIWindow?

        func attach(to window: UIWindow) {
            guard recognizer == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.recognizer = tap
            self.window = window
        }

        func detach() {
            if let recognizer { window?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            window = nil
        }

        @objc private func handleTap(_ sender: UITapGestureRecognizer) {
            guard let window else { return }
            let hit = window.hitTest(sender.location(in: window), with: nil)
            guard hit?.isInsideTextInput != true else { return }
            window.endEditing(true)
        }

        /// Never take the touch away from anything: every other recognizer on
        /// screen — the list's pan, the edge swipes, a row's own tap — keeps
        /// working alongside this one.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    /// True when the view, or anything it sits inside, is somewhere text is
    /// being typed. Walked upwards because the view actually hit is usually a
    /// private subview of the text view rather than the text view itself.
    var isInsideTextInput: Bool {
        var node: UIView? = self
        while let current = node {
            if current is UITextView || current is UITextField { return true }
            node = current.superview
        }
        return false
    }
}

extension View {
    /// See `KeyboardDismissTap`. Attach to a screen that has fields on it.
    func dismissesKeyboardOnOutsideTap() -> some View {
        background {
            KeyboardDismissTap()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

#endif
