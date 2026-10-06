import SwiftUI
import UIKit

/// Routes the user's pull-down of a SwiftUI sheet through the same policy as
/// the Cancel button, on iOS 15. Place it anywhere inside the sheet's content;
/// it finds the presented hosting controller through the parent chain and
/// becomes the presentation controller's delegate for that sheet only.
///
/// Whatever delegate SwiftUI installed is kept and still receives every
/// callback this adapter does not decide itself (notably `didDismiss`, which
/// SwiftUI may use to reset the `item` binding), so the sheet can be reopened
/// after an interactive close. No swizzling, no global appearance, no
/// retained strong reference to the sheet.
@available(iOS 15.0, *)
struct SheetDismissAdapter: UIViewControllerRepresentable {
    /// Asked on every pull-down. `true` lets the sheet go.
    let shouldDismiss: () -> Bool
    /// Called when a pull-down was refused (by `shouldDismiss` or by
    /// `isModalInPresentation`) so the sheet can show its confirmation.
    let onAttemptToDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AnchorViewController {
        let controller = AnchorViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: AnchorViewController, context: Context) {
        context.coordinator.shouldDismiss = shouldDismiss
        context.coordinator.onAttemptToDismiss = onAttemptToDismiss
        controller.attachIfNeeded()
    }

    static func dismantleUIViewController(_ controller: AnchorViewController, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class AnchorViewController: UIViewController {
        weak var coordinator: Coordinator?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.backgroundColor = .clear
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attachIfNeeded()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachIfNeeded()
        }

        /// The sheet is the top-most ancestor that is itself presented.
        func attachIfNeeded() {
            guard let coordinator else { return }
            var presented: UIViewController?
            var cursor: UIViewController? = self
            while let current = cursor {
                if current.presentingViewController != nil { presented = current }
                cursor = current.parent
            }
            guard let presented, let presentation = presented.presentationController else {
                #if DEBUG
                if parent != nil { NSLog("HelloProtein: SheetDismissAdapter found no presented sheet yet") }
                #endif
                return
            }
            coordinator.attach(to: presentation)
        }
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var shouldDismiss: () -> Bool = { true }
        var onAttemptToDismiss: () -> Void = {}
        private weak var presentation: UIPresentationController?
        /// SwiftUI's own delegate, kept so its bookkeeping keeps working. Held
        /// strongly while attached so a forwarded call can never reach a
        /// released object; released again in `detach()`.
        private var forwarded: UIAdaptivePresentationControllerDelegate?

        func attach(to presentation: UIPresentationController) {
            if self.presentation === presentation, presentation.delegate === self { return }
            detach()
            if let existing = presentation.delegate, existing !== self { forwarded = existing }
            self.presentation = presentation
            presentation.delegate = self
        }

        func detach() {
            guard let presentation, presentation.delegate === self else { return }
            presentation.delegate = forwarded
            self.presentation = nil
            forwarded = nil
        }

        // MARK: Decided here

        /// Both this sheet's policy and SwiftUI's own answer must allow it.
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            guard shouldDismiss() else { return false }
            return forwarded?.presentationControllerShouldDismiss?(presentationController) ?? true
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttemptToDismiss()
            forwarded?.presentationControllerDidAttemptToDismiss?(presentationController)
        }

        // MARK: Forwarded so SwiftUI's state stays correct

        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            forwarded?.presentationControllerWillDismiss?(presentationController)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            forwarded?.presentationControllerDidDismiss?(presentationController)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return forwarded?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if super.responds(to: aSelector) { return nil }
            if let forwarded, forwarded.responds(to: aSelector) { return forwarded }
            return nil
        }
    }
}
