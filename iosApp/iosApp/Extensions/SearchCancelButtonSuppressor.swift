#if os(iOS)
import SwiftUI
import UIKit

/// Hides the search bar's Cancel button (an "✕" pill on iOS 26) so the search
/// field's own clear button stays the single way to empty the query and the
/// navigation bar's back button stays the single way to leave the screen.
///
/// SwiftUI exposes no modifier for this, so the representable walks the
/// responder chain to the hosting controller and turns the button off on the
/// `UISearchController` that `.searchable` installed. Pair it with
/// `.searchPresentationToolbarBehavior(.avoidHidingContent)`, which keeps the
/// back button on screen while the field is focused.
///
/// It also lays the navigation bar out again once the push that shows the
/// screen finishes. Pushed from a page that hides its navigation bar (the tab
/// roots), a large title with an always-visible search drawer comes up with
/// the search bar laid out over the title, where it doesn't take taps, until
/// the next scroll lays the bar out again.
struct SearchCancelButtonSuppressor: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = SuppressorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class SuppressorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // The search controller is attached during the same layout pass
            // that installs this view, so apply on the next runloop turn.
            DispatchQueue.main.async { [weak self] in
                self?.suppressCancelButton()
            }
        }

        private func suppressCancelButton() {
            var responder: UIResponder? = self
            while let current = responder {
                if let viewController = current as? UIViewController,
                   let controller = viewController.navigationItem.searchController {
                    controller.automaticallyShowsCancelButton = false
                    controller.searchBar.setShowsCancelButton(false, animated: false)
                    relayoutNavigationBarAfterTransition(of: viewController)
                    return
                }
                responder = current.next
            }
        }

        private func relayoutNavigationBarAfterTransition(of viewController: UIViewController) {
            guard let coordinator = viewController.transitionCoordinator else { return }
            coordinator.animate(alongsideTransition: nil) { [weak viewController] _ in
                guard let bar = viewController?.navigationController?.navigationBar else { return }
                bar.setNeedsLayout()
                bar.layoutIfNeeded()
            }
        }
    }
}
#endif
