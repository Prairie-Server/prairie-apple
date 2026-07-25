#if os(iOS)
import Observation
import UIKit

/// SwiftUI app delegate bridge used only so UIKit asks our shared coordinator
/// which orientations are currently allowed.
final class PrairieAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        PlayerOrientationCoordinator.shared.supportedOrientations
    }
}

/// Centralized orientation policy for the iPhone player shell. Playback code
/// should stay unaware of this; the coordinator only manages UIKit masks and
/// scene geometry updates while the full-screen player is visible.
@Observable
final class PlayerOrientationCoordinator {
    static let shared = PlayerOrientationCoordinator()
    static let appDefaultOrientations: UIInterfaceOrientationMask = .allButUpsideDown

    private(set) var playerMode = PlayerSettings.shared.playerOrientationMode
    private(set) var isPlayerActive = false

    var supportedOrientations: UIInterfaceOrientationMask {
        guard isPlayerActive else { return Self.appDefaultOrientations }
        return playerMode.isLandscapeLocked ? .landscape : Self.appDefaultOrientations
    }

    private init() {}

    var isLandscapeLocked: Bool {
        playerMode.isLandscapeLocked
    }

    func activatePlayer() {
        playerMode = PlayerSettings.shared.playerOrientationMode
        isPlayerActive = true
        applyCurrentPolicy(rotateIntoLandscape: playerMode.isLandscapeLocked)
    }

    func deactivatePlayer() {
        isPlayerActive = false
        applyCurrentPolicy(rotateIntoLandscape: false, attemptDeviceRotation: true)
    }

    func togglePlayerMode() {
        setPlayerMode(playerMode.isLandscapeLocked ? .rotateFreely : .landscapeLocked)
    }

    func setPlayerMode(_ mode: PlayerOrientationMode) {
        guard playerMode != mode else { return }
        playerMode = mode
        PlayerSettings.shared.setPlayerOrientationMode(mode)
        guard isPlayerActive else { return }
        applyCurrentPolicy(
            rotateIntoLandscape: mode.isLandscapeLocked,
            attemptDeviceRotation: !mode.isLandscapeLocked
        )
    }

    private func applyCurrentPolicy(
        rotateIntoLandscape: Bool,
        attemptDeviceRotation: Bool = false
    ) {
        if Thread.isMainThread {
            updateOrientationPolicy(
                rotateIntoLandscape: rotateIntoLandscape,
                attemptDeviceRotation: attemptDeviceRotation
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateOrientationPolicy(
                    rotateIntoLandscape: rotateIntoLandscape,
                    attemptDeviceRotation: attemptDeviceRotation
                )
            }
        }
    }

    private func updateOrientationPolicy(
        rotateIntoLandscape: Bool,
        attemptDeviceRotation: Bool
    ) {
        let scenes = activeWindowScenes()
        for scene in scenes {
            for window in scene.windows {
                guard let rootViewController = window.rootViewController else { continue }
                notifyOrientationChange(for: rootViewController)
            }
        }

        // `requestGeometryUpdate(.iOS(interfaceOrientations:))` is the iOS 16+
        // replacement for the deprecated `attemptRotationToDeviceOrientation`
        // — it rotates the device on its own once `notifyOrientationChange`
        // has refreshed each VC's `supportedInterfaceOrientations`. The
        // `attemptDeviceRotation` flag is therefore only meaningful as a
        // signal that a follow-up policy refresh is desired post-rotate.
        let geometryMask = rotateIntoLandscape ? preferredLandscapeMask() : supportedOrientations
        guard let scene = scenes.first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: geometryMask)) { [weak self] _ in
            guard attemptDeviceRotation, let self else { return }
            for window in scene.windows {
                guard let rootViewController = window.rootViewController else { continue }
                self.notifyOrientationChange(for: rootViewController)
            }
        }
    }

    private func notifyOrientationChange(for viewController: UIViewController) {
        viewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        if let navigationController = viewController as? UINavigationController {
            navigationController.visibleViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        if let tabBarController = viewController as? UITabBarController {
            tabBarController.selectedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        if let presentedViewController = viewController.presentedViewController {
            notifyOrientationChange(for: presentedViewController)
        }
        for child in viewController.children {
            notifyOrientationChange(for: child)
        }
    }

    private func activeWindowScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter {
                $0.activationState == .foregroundActive
                    || $0.activationState == .foregroundInactive
            }
    }

    private func preferredLandscapeMask() -> UIInterfaceOrientationMask {
        if let interfaceOrientation = currentInterfaceOrientation() {
            switch interfaceOrientation {
            case .landscapeLeft:
                return .landscapeLeft
            case .landscapeRight:
                return .landscapeRight
            default:
                break
            }
        }

        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .landscapeRight
        }
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation? {
        activeWindowScenes()
            .map(\.effectiveGeometry.interfaceOrientation)
            .first(where: { $0 != .unknown })
    }
}
#endif
