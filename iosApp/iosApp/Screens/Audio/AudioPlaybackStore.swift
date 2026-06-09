import Foundation

@Observable
@MainActor
final class AudioPlaybackStore {
    let player = AudioPlayerViewModel()
    var isShowingFullPlayer = false
    private var lastRequest: AudioPlaybackRequest?

    func play(contentId: String, restart: Bool = false, startPosition: Double? = nil) {
        lastRequest = AudioPlaybackRequest(
            contentId: contentId,
            restart: restart,
            startPosition: startPosition
        )
        isShowingFullPlayer = true
        startLastRequest()
    }

    func retryLastRequest() {
        startLastRequest()
    }

    private func startLastRequest() {
        guard let lastRequest else { return }
        Task {
            await player.start(
                contentId: lastRequest.contentId,
                restart: lastRequest.restart,
                startPosition: lastRequest.startPosition
            )
        }
    }

    func showFullPlayer() {
        guard player.hasActiveSession else { return }
        isShowingFullPlayer = true
    }

    func dismissFullPlayer() {
        isShowingFullPlayer = false
    }
}

private struct AudioPlaybackRequest {
    let contentId: String
    let restart: Bool
    let startPosition: Double?
}
