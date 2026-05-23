import Foundation
import MediaPlayer
import OSLog
#if canImport(UIKit)
import UIKit
#endif

/// Bridges the active player core into `MPNowPlayingInfoCenter` + the shared
/// `MPRemoteCommandCenter` so lock-screen and Control Center media controls
/// drive playback. Apple TV 4K picks this up for the top-shelf Siri shortcut
/// (Play / Pause) and the phone gets the same dictionary on the lock screen.
///
/// Decoupled from any specific player type: the owner supplies command
/// handlers as closures via `attach(handlers:)`. This lets the controller
/// drive either `PlayerCore` (FFmpeg+VT pipeline) or `AVPlayerBackend` (DV
/// Profile 5 HLS route) transparently.
///
/// Single ownership: one instance per `PlayerViewModel`. The VM owns the
/// lifecycle (init in `loadAndPlay`, tear down in `cleanup`).
final class NowPlayingController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.continuum.app",
        category: "NowPlaying"
    )

    /// Command handlers the view model supplies. All fire on the main queue
    /// (the OS already dispatches remote commands there).
    struct Handlers {
        /// Called when the user presses Play on the lock screen / remote.
        var play: () -> Void
        /// Called when the user presses Pause.
        var pause: () -> Void
        /// True if currently paused. Used by togglePlayPause to decide
        /// which verb to fire.
        var isPaused: () -> Bool
        /// Absolute playback time in seconds, used by skip commands to
        /// compute the seek target.
        var currentTime: () -> Double
        /// Called with an absolute seek target in seconds.
        var seek: (Double) -> Void
    }

    private var handlers: Handlers?
    private var isActive = false
    /// URL of the artwork most recently requested. Used to dedupe fetches
    /// when `setArtworkURL` is called repeatedly with the same source while
    /// a fetch is already in flight or has already published.
    private var currentArtworkURL: URL?
    private var artworkFetchTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Attach command handlers. Idempotent — safe to call more than once to
    /// replace handlers when the VM swaps backends (e.g. PlayerCore →
    /// AVPlayer-backed route).
    func attach(handlers: Handlers) {
        self.handlers = handlers
        if !isActive {
            registerRemoteCommands()
            isActive = true
        }
    }

    func detach() {
        guard isActive else { return }
        isActive = false
        handlers = nil

        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        currentArtworkURL = nil

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(self)
        center.pauseCommand.removeTarget(self)
        center.togglePlayPauseCommand.removeTarget(self)
        center.skipForwardCommand.removeTarget(self)
        center.skipBackwardCommand.removeTarget(self)
        center.changePlaybackPositionCommand.removeTarget(self)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - State updates

    /// Refresh the Now Playing dictionary. Call on file-loaded, on
    /// time-change (≤1 Hz — do not flood), and on pause change. `isPlaying`
    /// feeds the playback-rate field which the OS uses to animate the
    /// scrubber between time updates.
    func update(title: String, duration: Double, position: Double, isPlaying: Bool) {
        guard isActive else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Fetch and publish poster artwork for the active item. Idempotent for
    /// the same URL — repeated calls with an unchanged URL no-op rather than
    /// re-fetching. Pass `nil` to clear the artwork field. Fetch happens on
    /// a background `URLSession.shared` data task; failures are logged and
    /// leave the existing artwork (if any) unchanged.
    func setArtworkURL(_ url: URL?) {
        guard isActive else { return }
        if currentArtworkURL == url {
            return
        }
        currentArtworkURL = url
        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        guard let url else {
            applyArtwork(nil)
            return
        }
        artworkFetchTask = Task { [weak self] in
            await self?.fetchAndApplyArtwork(url: url)
        }
    }

    private func fetchAndApplyArtwork(url: URL) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Self.logger.warning(
                    "Artwork fetch HTTP \(http.statusCode) for \(url.absoluteString, privacy: .public)"
                )
                return
            }
            #if canImport(UIKit)
            guard let image = UIImage(data: data) else {
                Self.logger.warning("Artwork decode failed for \(url.absoluteString, privacy: .public)")
                return
            }
            await MainActor.run { [weak self] in
                guard let self, self.isActive else { return }
                guard self.currentArtworkURL == url else { return }
                self.applyArtwork(image)
            }
            #else
            // macOS Now Playing doesn't take MPMediaItemArtwork the same way;
            // skip publishing rather than misuse the API.
            _ = data
            #endif
        } catch is CancellationError {
            return
        } catch {
            Self.logger.warning(
                "Artwork fetch failed for \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    #if canImport(UIKit)
    private func applyArtwork(_ image: UIImage?) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let image {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        } else {
            info[MPMediaItemPropertyArtwork] = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    #else
    private func applyArtwork(_ image: Any?) {
        // No-op on macOS for this client. macOS surfaces playback differently.
    }
    #endif

    // MARK: - Remote commands

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.handlers?.play()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handlers?.pause()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let h = self?.handlers else { return .commandFailed }
            if h.isPaused() {
                h.play()
            } else {
                h.pause()
            }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.addTarget { [weak self] event in
            guard let h = self?.handlers else { return .commandFailed }
            let skip = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            h.seek(h.currentTime() + skip)
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.addTarget { [weak self] event in
            guard let h = self?.handlers else { return .commandFailed }
            let skip = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            h.seek(max(0, h.currentTime() - skip))
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let h = self?.handlers,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            h.seek(positionEvent.positionTime)
            return .success
        }
    }
}
