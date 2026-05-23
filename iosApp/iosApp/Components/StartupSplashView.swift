import AVFoundation
import QuartzCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Full-screen startup animation shown while the app resolves its initial auth route.
struct StartupSplashView: View {
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    @State private var isVideoAvailable = true

    var body: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()

            if isVideoAvailable {
                StartupSplashPlayerSurface(player: player)
                    .ignoresSafeArea()
            } else {
                fallbackContent
            }
        }
        .accessibilityLabel("Loading Continuum")
        .onAppear(perform: startPlayback)
        .onDisappear(perform: stopPlayback)
    }

    private var fallbackContent: some View {
        VStack(spacing: 20) {
            SiloWordmarkView(width: 132)

            ProgressView()
                .tint(.continuumOnSurface)
                .scaleEffect(1.2)
        }
    }

    private func startPlayback() {
        if looper == nil {
            guard let url = Bundle.main.url(forResource: "startup_splash", withExtension: "mp4") else {
                isVideoAvailable = false
                return
            }

            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.isMuted = true
        }

        player.play()
    }

    private func stopPlayback() {
        player.pause()
    }
}

#if os(macOS)
private struct StartupSplashPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> StartupSplashPlayerLayerView {
        let view = StartupSplashPlayerLayerView()
        view.attach(player: player)
        return view
    }

    func updateNSView(_ nsView: StartupSplashPlayerLayerView, context: Context) {
        nsView.attach(player: player)
    }
}

private final class StartupSplashPlayerLayerView: NSView {
    private let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(player: AVPlayer) {
        if playerLayer.player === player { return }
        playerLayer.player = player
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
#else
private struct StartupSplashPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> StartupSplashPlayerLayerView {
        let view = StartupSplashPlayerLayerView()
        view.attach(player: player)
        return view
    }

    func updateUIView(_ uiView: StartupSplashPlayerLayerView, context: Context) {
        uiView.attach(player: player)
    }
}

private final class StartupSplashPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(player: AVPlayer) {
        if playerLayer.player === player { return }
        playerLayer.player = player
    }
}
#endif
