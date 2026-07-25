import SwiftUI
import AVKit

/// Minimal live player: AVPlayer over the session HLS URL. Releases the
/// server-side tuner session on dismiss so the tuner is freed promptly.
struct LiveTVPlayerView: View {
    let session: LiveTVPlayerSession
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var didRelease = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            Button {
                dismissAndRelease()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(20)
            }
            .accessibilityLabel("Close live TV")
        }
        .onAppear {
            let item = AVPlayerItem(url: session.hlsURL)
            let av = AVPlayer(playerItem: item)
            player = av
            av.play()
        }
        .onDisappear {
            releaseSessionIfNeeded()
            player?.pause()
            player = nil
        }
    }

    private func dismissAndRelease() {
        releaseSessionIfNeeded()
        player?.pause()
        onDismiss()
    }

    private func releaseSessionIfNeeded() {
        guard !didRelease else { return }
        didRelease = true
        let sessionId = session.sessionId
        Task {
            try? await ContinuumAPI.shared.releaseLiveTVSession(sessionId: sessionId)
        }
    }
}
