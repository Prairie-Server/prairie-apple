#if os(tvOS)
import AVFoundation
import AVKit
import Foundation
import OSLog
import UIKit

/// tvOS HDMI mode negotiation helpers. The compositor on Apple TV
/// chooses HDMI refresh rate and HDR mode based on
/// `AVDisplayManager.preferredDisplayCriteria`. PlayerCore drives this at
/// load time (when stream FPS / dynamic range are known) and on dispose
/// (to release the criteria so the system UI returns to its preferred
/// mode). The Profile-5 gate stays on PlayerCore because it owns the
/// observation lifetime.
enum TVDisplayCriteria {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.continuum.app.tvos",
        category: "TVDisplayCriteria"
    )

    static func activeTVWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            if let key = ws.windows.first(where: \.isKeyWindow) { return key }
            if let first = ws.windows.first { return first }
        }
        return nil
    }

    @MainActor
    static func apply(refreshRate: Float, dynamicRange: SpikeDynamicRange) {
        guard let dm = activeTVWindow()?.avDisplayManager else {
            logger.warning("apply: no avDisplayManager")
            print("[CMP] applyDisplayCriteria: no avDisplayManager (skipping HDMI negotiation)")
            return
        }
        guard dm.isDisplayCriteriaMatchingEnabled else {
            logger.info("apply: matching disabled")
            print("[CMP] applyDisplayCriteria: isDisplayCriteriaMatchingEnabled=false (user has 'Match Content' off)")
            return
        }
        let criteria = AVDisplayCriteria(refreshRate: refreshRate,
                                         videoDynamicRange: dynamicRange.rawValue)
        dm.preferredDisplayCriteria = criteria
        logger.info("apply: fps=\(refreshRate) dr=\(dynamicRange.rawValue)")
        print(String(format:
            "[CMP] applyDisplayCriteria APPLIED fps=%.3f dr=%d matching=true",
            Double(refreshRate), Int(dynamicRange.rawValue)))
    }

    static func clear(context: String) {
        DispatchQueue.main.async {
            guard let dm = activeTVWindow()?.avDisplayManager else {
                logger.warning("clear: no avDisplayManager")
                print("[CMP] clearDisplayCriteria context=\(context) manager=nil")
                return
            }
            dm.preferredDisplayCriteria = nil
            logger.info("clear context=\(context)")
            print("[CMP] clearDisplayCriteria context=\(context) switchInProgress=\(dm.isDisplayModeSwitchInProgress ? 1 : 0)")
        }
    }
}
#endif
