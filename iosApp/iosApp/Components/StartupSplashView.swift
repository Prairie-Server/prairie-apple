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
    private static let fallbackDuration: TimeInterval = 4.0

    let onFinished: () -> Void

    @State private var player = AVPlayer()
    @State private var playerItem: AVPlayerItem?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var playbackEndObserver: NSObjectProtocol?
    @State private var playbackFailureObserver: NSObjectProtocol?
    @State private var fallbackCompletionTask: Task<Void, Never>?
    @State private var isVideoAvailable = true
    @State private var didFinish = false

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
        if playerItem == nil {
            guard let url = Bundle.main.url(forResource: "startup_splash", withExtension: "mp4") else {
                isVideoAvailable = false
                scheduleFallbackCompletion()
                return
            }

            let item = AVPlayerItem(url: url)
            playerItem = item
            player.replaceCurrentItem(with: item)
            player.isMuted = true
            installPlaybackObservers(for: item)
            installStatusObservation(for: item)
        }

        player.play()
    }

    private func stopPlayback() {
        player.pause()
        fallbackCompletionTask?.cancel()
        fallbackCompletionTask = nil
        removePlaybackObservers()
        removeStatusObservation()
    }

    private func installPlaybackObservers(for item: AVPlayerItem) {
        removePlaybackObservers()

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            finish()
        }

        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isVideoAvailable = false
            scheduleFallbackCompletion()
        }
    }

    private func installStatusObservation(for item: AVPlayerItem) {
        removeStatusObservation()
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                isVideoAvailable = false
                scheduleFallbackCompletion()
            }
        }
    }

    private func removePlaybackObservers() {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
            self.playbackFailureObserver = nil
        }
    }

    private func removeStatusObservation() {
        statusObservation?.invalidate()
        statusObservation = nil
    }

    private func scheduleFallbackCompletion() {
        guard fallbackCompletionTask == nil else { return }
        fallbackCompletionTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.fallbackDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { finish() }
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        fallbackCompletionTask?.cancel()
        fallbackCompletionTask = nil
        removePlaybackObservers()
        removeStatusObservation()
        onFinished()
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
