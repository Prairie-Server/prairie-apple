#if os(macOS)
import AppKit
import AVFoundation
import SwiftUI

struct PlayerSurface: NSViewRepresentable {
    let player: PlayerCore

    func makeNSView(context: Context) -> PlayerSurfaceHostView {
        let view = PlayerSurfaceHostView()
        view.attach(player: player)
        return view
    }

    func updateNSView(_ nsView: PlayerSurfaceHostView, context: Context) {
        nsView.attach(player: player)
    }
}

final class PlayerSurfaceHostView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private weak var attachedPlayer: PlayerCore?
    private let subtitleOverlay = SubtitleOverlayView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)
        updateDisplayLayerScale()

        subtitleOverlay.autoresizingMask = []
        addSubview(subtitleOverlay, positioned: .above, relativeTo: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(player: PlayerCore) {
        if attachedPlayer === player { return }
        attachedPlayer = player
        player.attach(to: displayLayer)
        subtitleOverlay.renderer = player.subtitleRendererForOverlay
        player.subtitleOverlay = subtitleOverlay
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
        subtitleOverlay.frame = bounds
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDisplayLayerScale()
    }

    private func updateDisplayLayerScale() {
        displayLayer.contentsScale = layer?.contentsScale
            ?? window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
    }
}
#endif
