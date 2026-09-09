#if os(iOS)
import SwiftUI
import UIKit

/// Restores the two edge gestures the app's own chrome takes away.
///
/// Every screen here hides the navigation bar and draws its own back button,
/// and UIKit reads a hidden bar as "this screen opts out of the interactive
/// pop" — so swiping in from the left edge does nothing, and the only way back
/// is the button. That is the wrong trade on a phone: the edge swipe is how
/// iOS is navigated, and a screen that ignores it feels broken long before
/// anyone notices the button.
///
/// So this reaches the `UINavigationController` that `NavigationStack` is built
/// on and (a) re-arms its pop recognizer with a delegate that allows the swipe
/// whenever there is something to pop, and (b) adds the mirror of it on the
/// right edge, which puts back the screen that swipe just dismissed — an undo
/// for the gesture, in the direction the page left in.
///
/// Mount it as a zero-size background inside the stack's root, not on a pushed
/// screen: it has to outlive the pushes it is arbitrating.
struct NavigationGestureBridge: UIViewControllerRepresentable {
    /// Whether there is a popped screen to put back.
    var canGoForward: () -> Bool
    /// Re-push it.
    var goForward: () -> Void

    func makeUIViewController(context: Context) -> BridgeController {
        let controller = BridgeController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: BridgeController, context: Context) {
        context.coordinator.canGoForward = canGoForward
        context.coordinator.goForward = goForward
        // Re-run on every update: SwiftUI rebuilds the pop recognizer's own
        // delegate as screens come and go, and whatever it installs last would
        // otherwise win back the veto we are trying to remove.
        controller.install()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The name the forward recognizer is tagged with, so the shared delegate
    /// can tell it apart from UIKit's own pop recognizer and so `install()`
    /// never adds a second copy.
    fileprivate static let forwardGestureName = "com.kiransreminderapp.forwardEdgePan"

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canGoForward: () -> Bool = { false }
        var goForward: () -> Void = {}
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            if recognizer.name == NavigationGestureBridge.forwardGestureName {
                return canGoForward()
            }
            // The pop gesture. Guarding on the stack depth is the whole reason
            // this delegate exists rather than a nil one: letting the swipe
            // begin on the root screen starts a transition UIKit can never
            // finish, and the stack stops responding to pushes afterwards.
            return (navigationController?.viewControllers.count ?? 0) > 1
        }

        /// The edge swipes own the gesture outright. Letting a list's own pan
        /// run alongside them means a back swipe that also scrolls the page it
        /// is leaving.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            false
        }

        @objc func handleForwardSwipe(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let translation = recognizer.translation(in: recognizer.view).x
            let velocity = recognizer.velocity(in: recognizer.view).x
            // Committed at either a third of the way across or a flick. The
            // push itself is animated rather than tracking the finger: UIKit
            // gives no interactive driver for a push, and a half-followed
            // gesture that snaps at the end reads worse than a clean one.
            let width = recognizer.view?.bounds.width ?? UIScreen.main.bounds.width
            guard translation < -width / 3 || velocity < -600 else { return }
            guard canGoForward() else { return }
            goForward()
        }
    }

    /// A view controller with no view of its own, there only to be adopted by
    /// the navigation controller so it can find it.
    final class BridgeController: UIViewController {
        var coordinator: Coordinator?
        private var forwardGestureInstalled = false

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        func install() {
            guard let coordinator, let nav = enclosingNavigationController else { return }
            coordinator.navigationController = nav

            if let pop = nav.interactivePopGestureRecognizer {
                pop.isEnabled = true
                pop.delegate = coordinator
            }

            guard !forwardGestureInstalled else { return }
            let forward = UIScreenEdgePanGestureRecognizer(
                target: coordinator,
                action: #selector(Coordinator.handleForwardSwipe(_:))
            )
            forward.edges = .right
            forward.name = NavigationGestureBridge.forwardGestureName
            forward.delegate = coordinator
            nav.view.addGestureRecognizer(forward)
            forwardGestureInstalled = true
        }

        /// `navigationController` is nil for a child controller SwiftUI hangs
        /// off a background, so walk up until a stack turns up.
        private var enclosingNavigationController: UINavigationController? {
            if let nav = navigationController { return nav }
            var next = parent
            while let current = next {
                if let nav = current as? UINavigationController { return nav }
                if let nav = current.navigationController { return nav }
                next = current.parent
            }
            return nil
        }
    }
}

extension View {
    /// See `NavigationGestureBridge`. Attach inside a `NavigationStack`'s root.
    func navigationEdgeGestures(
        canGoForward: @escaping () -> Bool,
        goForward: @escaping () -> Void
    ) -> some View {
        background {
            NavigationGestureBridge(canGoForward: canGoForward, goForward: goForward)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

#endif
