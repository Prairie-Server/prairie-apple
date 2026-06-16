#if os(iOS)
import SwiftUI

/// Native "now-playing" remote for controlling Silo playback on an Apple TV.
/// Thin wrapper: observes the cast session and drives the presentational
/// `RemoteNowPlayingContent` with plain state + a command callback.
struct SiloCastRemoteControlView: View {
    @Bindable var controller: SiloCastController
    @Environment(\.dismiss) private var dismiss
    @State private var artwork = SiloCastArtworkResolver()
    @State private var isShowingPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                SiloCastArtworkBackground(urlString: artwork.backdropURL ?? artwork.posterURL)
                content
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        controller.hideRemoteControl()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Minimize")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingPicker = true
                        } label: {
                            Label("Choose a Different TV", systemImage: "tv")
                        }
                        Button {
                            controller.send(.stop)
                        } label: {
                            Label("Stop Playback", systemImage: "stop.fill")
                        }
                        Divider()
                        Button(role: .destructive) {
                            controller.disconnect()
                            dismiss()
                        } label: {
                            Label("Disconnect", systemImage: "tv.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("More options")
                }
            }
            .sheet(isPresented: $isShowingPicker) {
                SiloCastTargetPickerView(request: nil, controller: controller)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: controller.state?.contentId) {
            await artwork.resolve(contentId: controller.state?.contentId)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let state = controller.state {
            RemoteNowPlayingContent(
                state: state,
                targetName: controller.activeTarget?.name,
                posterURL: artwork.posterURL ?? artwork.backdropURL,
                onCommand: { controller.send($0) }
            )
        } else {
            connectingView
        }
    }

    private var connectingView: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.continuumSurfaceElevated)
                .frame(width: 150, height: 216)
            if let error = controller.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Color.continuumOnSurface)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.continuumError.opacity(0.9)))
            } else {
                ProgressView()
                Text("Connecting to \(controller.activeTarget?.name ?? "Silo TV")…")
                    .font(.headline)
                    .foregroundStyle(Color.continuumSecondaryText)
            }
        }
        .padding(24)
    }
}

/// Pure presentational now-playing layout — no controller dependency, so it
/// previews with mock `SiloCastPlaybackState`.
private struct RemoteNowPlayingContent: View {
    let state: SiloCastPlaybackState
    let targetName: String?
    let posterURL: String?
    let onCommand: (SiloCastControlCommand) -> Void

    @State private var scrubPreview: Double?
    private let speedOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            artwork
            Spacer(minLength: 16)
            titleBlock
            playingOnPill.padding(.top, 10)
            scrubber.padding(.top, 22)
            transport.padding(.top, 18)
            Spacer(minLength: 16)
            secondaryControls
            if let error = state.error, !error.isEmpty {
                errorBanner(error).padding(.top, 12)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var artwork: some View {
        Group {
            if let posterURL, !posterURL.isEmpty {
                AsyncImageView(url: posterURL, contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.continuumSurfaceElevated)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay {
                        Image(systemName: "tv")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.continuumSecondaryText)
                    }
            }
        }
        .frame(maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(state.title.isEmpty ? "Loading" : state.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(Color.continuumOnSurface)
            if let subtitle = state.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(Color.continuumSecondaryText)
            }
        }
    }

    @ViewBuilder
    private var playingOnPill: some View {
        if let targetName, !targetName.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 12, weight: .semibold))
                Text("Playing on \(targetName)")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.continuumSecondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.continuumChromeRestingFill))
        }
    }

    private var scrubber: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { scrubPreview ?? state.currentTime },
                    set: { scrubPreview = $0 }
                ),
                in: 0...max(state.duration, 1),
                onEditingChanged: { editing in
                    guard !editing, let scrubPreview else { return }
                    onCommand(.seek(seconds: scrubPreview))
                    self.scrubPreview = nil
                }
            )
            .tint(Color.continuumOnSurface)
            .disabled(state.duration <= 0)
            .accessibilityLabel("Playback position")

            HStack {
                Text(PlayerTimeFormatter.formatHMS(scrubPreview ?? state.currentTime))
                Spacer()
                Text(remainingLabel)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.continuumSecondaryText)
        }
    }

    private var remainingLabel: String {
        guard state.duration > 0 else { return PlayerTimeFormatter.formatHMS(state.duration) }
        let remaining = max(0, state.duration - (scrubPreview ?? state.currentTime))
        return "-" + PlayerTimeFormatter.formatHMS(remaining)
    }

    private var transport: some View {
        HStack(spacing: 36) {
            Button {
                onCommand(.seek(seconds: max(0, state.currentTime - 10)))
            } label: {
                Image(systemName: "gobackward.10").font(.system(size: 30, weight: .regular))
            }
            .accessibilityLabel("Back 10 seconds")

            Button {
                onCommand(.playPause)
            } label: {
                ZStack {
                    Circle().fill(Color.continuumOnSurface).frame(width: 64, height: 64)
                    if state.isLoading || state.isBuffering {
                        ProgressView().tint(Color.continuumBackground)
                    } else {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.continuumBackground)
                    }
                }
            }
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")

            Button {
                let target = state.duration > 0 ? min(state.duration, state.currentTime + 30) : state.currentTime + 30
                onCommand(.seek(seconds: target))
            } label: {
                Image(systemName: "goforward.30").font(.system(size: 30, weight: .regular))
            }
            .accessibilityLabel("Forward 30 seconds")
        }
        .foregroundStyle(Color.continuumOnSurface)
        .buttonStyle(.plain)
    }

    private var secondaryControls: some View {
        HStack(alignment: .top, spacing: 8) {
            if !state.audioTracks.isEmpty {
                audioMenu.frame(maxWidth: .infinity)
            }
            if !state.subtitleTracks.isEmpty {
                subtitleMenu.frame(maxWidth: .infinity)
            }
            if !state.qualityOptions.isEmpty {
                qualityMenu.frame(maxWidth: .infinity)
            }
            speedMenu.frame(maxWidth: .infinity)
            if state.supportsVideoGravity || state.supportsHDRToggle {
                displayMenu.frame(maxWidth: .infinity)
            }
        }
    }

    private var audioMenu: some View {
        Menu {
            ForEach(state.audioTracks) { track in
                Button { onCommand(.selectAudioTrack(track.trackId)) } label: {
                    Label(track.title, systemImage: state.selectedAudioTrackId == track.trackId ? "checkmark" : "waveform")
                }
            }
        } label: { RemoteChipLabel(systemImage: "waveform", caption: "Audio") }
        .accessibilityValue(state.audioTracks.first(where: { $0.trackId == state.selectedAudioTrackId })?.title ?? "None")
    }

    private var subtitleMenu: some View {
        Menu {
            Button { onCommand(.selectSubtitleTrack(nil)) } label: {
                Label("Off", systemImage: state.selectedSubtitleTrackId == nil ? "checkmark" : "captions.bubble")
            }
            ForEach(state.subtitleTracks) { track in
                Button { onCommand(.selectSubtitleTrack(track.trackId)) } label: {
                    Label(track.title, systemImage: state.selectedSubtitleTrackId == track.trackId ? "checkmark" : "captions.bubble")
                }
            }
        } label: { RemoteChipLabel(systemImage: "captions.bubble", caption: "Subtitles") }
        .accessibilityValue(state.subtitleTracks.first(where: { $0.trackId == state.selectedSubtitleTrackId })?.title ?? "Off")
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(state.qualityOptions) { option in
                Button { onCommand(.setQuality(option.id)) } label: {
                    Label(option.label, systemImage: state.activeQualityId == option.id ? "checkmark" : "slider.horizontal.3")
                }
            }
        } label: { RemoteChipLabel(systemImage: "slider.horizontal.3", caption: "Quality") }
        .accessibilityValue(state.qualityOptions.first(where: { $0.id == state.activeQualityId })?.label ?? state.activeQualityId)
        .disabled(state.isQualitySwitching)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(speedOptions, id: \.self) { speed in
                Button { onCommand(.setPlaybackSpeed(speed)) } label: {
                    Label(speedLabel(speed), systemImage: abs(state.playbackSpeed - speed) < 0.01 ? "checkmark" : "speedometer")
                }
            }
        } label: { RemoteChipLabel(systemImage: "speedometer", caption: "Speed") }
        .accessibilityValue(speedLabel(state.playbackSpeed))
    }

    private var displayMenu: some View {
        Menu {
            if state.supportsVideoGravity {
                ForEach(VideoGravity.allCases, id: \.rawValue) { gravity in
                    Button { onCommand(.setVideoGravity(gravity.rawValue)) } label: {
                        Label(gravity.label, systemImage: state.videoGravity == gravity.rawValue ? "checkmark" : "rectangle.inset.filled")
                    }
                }
            }
            if state.supportsHDRToggle {
                Button { onCommand(.setHDREnabled(!state.hdrEnabled)) } label: {
                    Label(state.hdrEnabled ? "HDR On" : "HDR Off", systemImage: state.hdrEnabled ? "checkmark" : "sun.max")
                }
            }
        } label: { RemoteChipLabel(systemImage: "rectangle.inset.filled", caption: "Aspect") }
        .accessibilityValue(VideoGravity(rawValue: state.videoGravity)?.label ?? state.videoGravity)
    }

    private func speedLabel(_ speed: Double) -> String {
        switch speed {
        case 1.0: return "1.0×"
        case 0.75: return "0.75×"
        case 1.25: return "1.25×"
        case 1.5: return "1.5×"
        case 2.0: return "2.0×"
        default: return "\(speed)×"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Color.continuumOnSurface)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.continuumError.opacity(0.9)))
    }
}

private struct RemoteChipLabel: View {
    let systemImage: String
    let caption: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
            Text(caption)
                .font(.caption2)
        }
        .foregroundStyle(Color.continuumOnSurface.opacity(0.9))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

#if DEBUG
private extension SiloCastPlaybackState {
    static func previewPlaying() -> SiloCastPlaybackState {
        SiloCastPlaybackState(
            contentId: "preview", sessionId: "s1", title: "The Bear",
            subtitle: "Season 3 · Episode 4 · Children",
            isPlaying: true, isLoading: false, isBuffering: false,
            currentTime: 1104, duration: 2895,
            audioTracks: [SiloCastTrack(kind: "audio", trackId: 1, title: "English 5.1", detail: "AC-3")],
            subtitleTracks: [SiloCastTrack(kind: "subtitle", trackId: 10, title: "English", detail: nil)],
            selectedAudioTrackId: 1, selectedSubtitleTrackId: nil,
            qualityOptions: [SiloCastOption(id: "auto", label: "Auto", detail: nil),
                             SiloCastOption(id: "1080", label: "1080p", detail: nil)],
            activeQualityId: "auto", isQualitySwitching: false,
            playbackSpeed: 1.0, videoGravity: VideoGravity.fit.rawValue, hdrEnabled: false,
            supportsVideoGravity: true, supportsHDRToggle: true,
            volume: 1.0,
            isMuted: false,
            hasNextEpisode: false,
            nextEpisodeTitle: nil,
            error: nil
        )
    }
}

#Preview("Now Playing") {
    ZStack {
        SiloCastArtworkBackground(urlString: nil)
        RemoteNowPlayingContent(
            state: .previewPlaying(),
            targetName: "Living Room",
            posterURL: nil,
            onCommand: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
#endif
#endif
