#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum PlatformScreen {
    static var mainBounds: CGRect {
        #if canImport(UIKit)
        #if os(tvOS)
        return CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #else
        return activeScreen?.bounds ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #endif
        #elseif canImport(AppKit)
        return NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        #endif
    }

    static var maximumFramesPerSecond: Double? {
        #if canImport(UIKit)
        #if os(tvOS)
        return 60
        #else
        guard let fps = activeScreen?.maximumFramesPerSecond, fps > 0 else { return nil }
        return Double(fps)
        #endif
        #elseif canImport(AppKit)
        guard let fps = NSScreen.main?.maximumFramesPerSecond, fps > 0 else { return nil }
        return Double(fps)
        #endif
    }

    #if canImport(UIKit) && !os(tvOS)
    private static var activeScreen: UIScreen? {
        return UIScreen.main
    }
    #endif
}
