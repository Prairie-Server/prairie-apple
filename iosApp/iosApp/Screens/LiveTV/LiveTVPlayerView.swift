import SwiftUI
import AVKit

/// Live player: AVPlayer over an authenticated HLS session URL. MPEG-TS
/// sessions show an explanatory error because AVPlayer cannot play them.
/// Releases the server-side tuner session on dismiss.
struct LiveTVPlayerView: View {
    let session: LiveTVPlayerSession
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var playbackError: String?
    @State private var didRelease = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if !session.isHLS {
                unsupportedTransportView
            } else if let playbackError {
                playbackErrorView(playbackError)
            } else if let player {
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
        .task {
            guard session.isHLS else { return }
            await startHLSPlayback()
        }
        .onDisappear {
            releaseSessionIfNeeded()
            player?.pause()
            player = nil
        }
    }

    private var unsupportedTransportView: some View {
        playbackErrorView(
            "Live MPEG-TS playback isn't supported on Apple devices. "
                + "Ask your server admin to enable HLS transcoding for Live TV."
        )
    }

    private func playbackErrorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.slash")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.85))
            Text(message)
                .font(.continuumBody)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("livetv-player-error")
    }

    private func startHLSPlayback() async {
        guard let url = session.streamURL else {
            playbackError = "Live stream URL missing"
            return
        }

        let headers = await Self.authHeaders()
        var options: [String: Any] = [:]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let av = AVPlayer(playerItem: item)
        player = av
        av.play()
    }

    /// Same header contract as `AudioPlayerEngine` / `AVPlayerBackend`.
    private static func authHeaders() async -> [String: String] {
        var headers: [String: String] = [:]
        if let token = await TokenStore.shared.getAccessToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        if let profileId = await TokenStore.shared.getProfileId() {
            headers["X-Profile-Id"] = profileId
        }
        if let profileToken = await TokenStore.shared.getProfileToken() {
            headers["X-Profile-Token"] = profileToken
        }
        return headers
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

/// Identifiable hand-off into the live player.
struct LiveTVPlayerSession: Identifiable, Hashable {
    let id = UUID()
    let sessionId: String
    let streamURL: URL?
    let title: String
    let isHLS: Bool
}
