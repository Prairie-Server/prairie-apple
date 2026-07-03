//
//  SubtitleOverlayView.swift
//  Continuum (Apple platforms)
//
//  Composites libass output onto the player surface. Sits above the
//  `AVSampleBufferDisplayLayer` inside `PlayerSurfaceHostView`. Pinned
//  to all four edges — libass handles the subtitle positioning via its
//  frame-size + margins model, so this view is always full-frame.
//
//  The view holds a single `CALayer.contents` CGImage that the
//  `SubtitleRenderer` produces on its dedicated queue. We don't compose
//  on the main thread; we only assign the already-baked image.
//

import CoreGraphics
import QuartzCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private func withoutImplicitLayerAnimation(_ updates: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    updates()
    CATransaction.commit()
}

#if canImport(UIKit)
final class SubtitleOverlayView: UIView {

    /// Strong reference to the renderer. Held here (not just via the
    /// session) because the overlay's `layoutSubviews` notifies the
    /// renderer of frame-size changes directly.
    weak var renderer: SubtitleRenderer?

    /// Distance from this overlay's edges to the displayed video rect.
    /// Zero when the host sizes the overlay to the video rect (iOS);
    /// set by the tvOS hosts, which size the overlay to the full frame so
    /// libass can place the "Bottom" preset in the letterbox bar.
    var videoInsets: SubtitleVideoInsets = .zero {
        didSet {
            guard videoInsets != oldValue else { return }
            pushFrameGeometry()
        }
    }

    /// Layer that holds the composited subtitle image. Separate from
    /// `self.layer` so we can swap its `contents` without disturbing
    /// any other decoration the view might grow in the future.
    private let contentsLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        // Overlay sits above the AVSampleBufferDisplayLayer; having
        // its own layer inside makes the z-order explicit.
        contentsLayer.contentsGravity = .resizeAspectFill
        contentsLayer.isOpaque = false
        layer.addSublayer(contentsLayer)
        // The composited image is a libass-rendered bitmap, not text.
        // Without a textual representation VoiceOver would either announce
        // a misleading static label or read raw image-element noise; hide
        // the overlay from accessibility instead. Once the renderer
        // exposes the active event text, this can be replaced with a
        // proper `accessibilityValue` binding.
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutImplicitLayerAnimation {
            contentsLayer.frame = bounds
        }
        pushFrameGeometry()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Window change can mean a new screen scale (external display,
        // airplay). Re-push frame size so libass re-paints at the right
        // pixel density.
        if window != nil {
            pushFrameGeometry()
        }
    }

    private func pushFrameGeometry() {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        withoutImplicitLayerAnimation {
            contentsLayer.contentsScale = scale
        }
        renderer?.updateFrameSize(bounds.size, scale: scale, videoInsets: videoInsets)
    }

    /// Assign the newest composited image. Call on main thread.
    func updateContents(_ image: CGImage?) {
        // CALayer.contents takes `Any?` — pass `image` directly to avoid
        // the ARC/CFType dance of an explicit `as CGImage`.
        withoutImplicitLayerAnimation {
            contentsLayer.contents = image
        }
    }

    /// Clear the overlay immediately. Used on track disable / playback
    /// teardown.
    func clear() {
        withoutImplicitLayerAnimation {
            contentsLayer.contents = nil
        }
    }
}
#elseif canImport(AppKit)
final class SubtitleOverlayView: NSView {
    /// Strong reference to the renderer. Held here (not just via the
    /// session) because layout notifies the renderer of frame-size changes
    /// directly.
    weak var renderer: SubtitleRenderer?

    /// Distance from this overlay's edges to the displayed video rect.
    /// Always zero on macOS (the hosts size the overlay to the video rect);
    /// present so shared pump code can read it uniformly.
    var videoInsets: SubtitleVideoInsets = .zero {
        didSet {
            guard videoInsets != oldValue else { return }
            updateLayout()
        }
    }

    /// Layer that holds the composited subtitle image. Separate from
    /// `self.layer` so we can swap its `contents` without disturbing the
    /// hosting `AVPlayerView`.
    private let contentsLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.zPosition = 10_000
        layer?.isOpaque = false
        layer?.masksToBounds = false
        contentsLayer.contentsGravity = .resizeAspectFill
        contentsLayer.isOpaque = false
        contentsLayer.zPosition = 10_000
        layer?.addSublayer(contentsLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func layout() {
        super.layout()
        updateLayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayout()
    }

    private func updateLayout() {
        withoutImplicitLayerAnimation {
            contentsLayer.frame = bounds
        }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        withoutImplicitLayerAnimation {
            contentsLayer.contentsScale = scale
        }
        renderer?.updateFrameSize(bounds.size, scale: scale, videoInsets: videoInsets)
    }

    /// Assign the newest composited image. Call on main thread.
    func updateContents(_ image: CGImage?) {
        withoutImplicitLayerAnimation {
            contentsLayer.contents = image
        }
    }

    /// Clear the overlay immediately. Used on track disable / playback
    /// teardown.
    func clear() {
        withoutImplicitLayerAnimation {
            contentsLayer.contents = nil
        }
    }
}
#endif
