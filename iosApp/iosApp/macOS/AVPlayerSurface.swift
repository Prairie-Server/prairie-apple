#if os(macOS)
import AVKit
import SwiftUI

struct AVPlayerSurface: NSViewRepresentable {
    let backend: AVPlayerBackend

    func makeNSView(context: Context) -> ContinuumMacPlayerView {
        let view = ContinuumMacPlayerView()
        view.attach(player: backend.avPlayer)
        view.attachSubtitleRenderer(backend.subtitleRendererForOverlay)
        backend.subtitleOverlay = view.subtitleOverlay
        return view
    }

    func updateNSView(_ nsView: ContinuumMacPlayerView, context: Context) {
        nsView.attach(player: backend.avPlayer)
        nsView.attachSubtitleRenderer(backend.subtitleRendererForOverlay)
        backend.subtitleOverlay = nsView.subtitleOverlay
    }
}

final class ContinuumMacPlayerView: AVPlayerView {
    let subtitleOverlay = SubtitleOverlayView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        controlsStyle = .none
        videoGravity = .resizeAspect
        showsFrameSteppingButtons = false
        showsFullScreenToggleButton = true
        showsSharingServiceButton = false
        updatesNowPlayingInfoCenter = false
        addSubtitleOverlay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(player: AVPlayer) {
        if self.player === player { return }
        self.player = player
    }

    func attachSubtitleRenderer(_ renderer: SubtitleRenderer?) {
        subtitleOverlay.renderer = renderer
    }

    private func addSubtitleOverlay() {
        subtitleOverlay.autoresizingMask = []
        subtitleOverlay.wantsLayer = true
        overlayParent.addSubview(subtitleOverlay, positioned: .above, relativeTo: nil)
    }

    private func positionSubtitleOverlays() {
        overlayParent.addSubview(subtitleOverlay, positioned: .above, relativeTo: nil)
    }

    override func layout() {
        super.layout()
        let frame = videoBounds.isEmpty ? bounds : videoBounds
        subtitleOverlay.frame = frame
    }

    private var overlayParent: NSView {
        contentOverlayView ?? self
    }
}
#endif
