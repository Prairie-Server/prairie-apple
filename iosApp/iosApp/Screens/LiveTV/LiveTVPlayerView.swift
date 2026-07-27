import SwiftUI
import AVKit

/// Live player: AVPlayer over an authenticated HLS session URL. Query params
/// on the manifest keep segment fetches authed; headers cover the first fetch.
/// Releases the server-side tuner session on dismiss.
struct LiveTVPlayerView: View {
    let session: LiveTVPlayerSession
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var playbackError: String?
    @State private var didRelease = false
    @State private var itemStatusObservation: NSKeyValueObservation?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let playbackError {
                playbackErrorView(playbackError)
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if shouldAttemptPlayback {
                ProgressView()
                    .tint(.white)
            } else {
                playbackErrorView("Live stream URL missing")
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
            await startPlaybackIfPossible()
        }
        .onDisappear {
            itemStatusObservation?.invalidate()
            itemStatusObservation = nil
            releaseSessionIfNeeded()
            player?.pause()
            player = nil
        }
    }

    /// Attempt playback whenever the session exposes a stream URL.
    private var shouldAttemptPlayback: Bool {
        session.streamURL != nil
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

    private func startPlaybackIfPossible() async {
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
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                playbackError = item.error?.localizedDescription ?? "Unable to play live stream"
            }
        }
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
