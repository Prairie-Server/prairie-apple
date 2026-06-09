import SwiftUI

struct AudioMiniPlayerView: View {
    @Environment(AudioPlaybackStore.self) private var audioStore

    var body: some View {
        let player = audioStore.player
        if player.hasActiveSession {
            HStack(spacing: 12) {
                Button {
                    audioStore.showFullPlayer()
                } label: {
                    HStack(spacing: 12) {
                        AudioCoverView(urlString: player.posterUrl, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.title)
                                .font(.subheadline)
                                .bold()
                                .lineLimit(1)
                            Text(player.subtitle ?? currentChapterTitle(player: player))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now Playing")

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(
                            width: proxy.size.width * progressFraction(player: player),
                            height: 2
                        )
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func progressFraction(player: AudioPlayerViewModel) -> CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(max(player.currentTime / player.duration, 0), 1))
    }

    private func currentChapterTitle(player: AudioPlayerViewModel) -> String {
        player.chapters
            .sorted { $0.startSeconds < $1.startSeconds }
            .last(where: { $0.startSeconds <= player.currentTime })?
            .title ?? PlayerTimeFormatter.formatHMS(player.currentTime)
    }
}

struct AudioFullPlayerView: View {
    @Environment(AudioPlaybackStore.self) private var audioStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let player = audioStore.player
        NavigationStack {
            content(player: player)
            .continuumBackground()
            .navigationTitle("Now Playing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        audioStore.dismissFullPlayer()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await player.close()
                            audioStore.dismissFullPlayer()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Stop")
                }
            }
        }
    }

    @ViewBuilder
    private func content(player: AudioPlayerViewModel) -> some View {
        if player.isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Starting audiobook")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = player.error {
            ErrorView(
                state: error,
                onRetry: { audioStore.retryLastRequest() }
            )
        } else if player.hasActiveSession {
            playerContent(player: player)
        } else {
            EmptyStateView(
                icon: "headphones",
                title: "No audiobook playing",
                subtitle: nil
            )
        }
    }

    private func playerContent(player: AudioPlayerViewModel) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                AudioCoverView(urlString: player.posterUrl, size: 260)
                    .padding(.top, 28)

                VStack(spacing: 6) {
                    Text(player.title)
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)
                    if let subtitle = player.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)

                AudioProgressScrubber(player: player)
                    .padding(.horizontal)

                AudioTransportControls(player: player)

                AudioPlayerOptions(player: player)

                if !player.chapters.isEmpty {
                    AudioChapterList(player: player)
                }
            }
            .padding(.bottom, 32)
        }
    }
}

private struct AudioTransportControls: View {
    let player: AudioPlayerViewModel

    var body: some View {
        HStack(spacing: 26) {
            Button {
                player.previousChapter()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous Chapter")

            Button {
                player.skip(by: -30)
            } label: {
                Image(systemName: "gobackward.30")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back 30 Seconds")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
                    .frame(width: 76, height: 76)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                player.skip(by: 30)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Forward 30 Seconds")

            Button {
                player.nextChapter()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next Chapter")
        }
        .buttonStyle(.plain)
    }
}

private struct AudioProgressScrubber: View {
    let player: AudioPlayerViewModel
    @State private var displayedTime: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 8) {
            #if os(tvOS)
            HStack(spacing: 16) {
                Button {
                    player.skip(by: -30)
                } label: {
                    Image(systemName: "gobackward.30")
                        .frame(width: 52, height: 44)
                }
                .accessibilityLabel("Back 30 Seconds")

                ProgressView(
                    value: min(max(player.currentTime, 0), max(player.duration, 1)),
                    total: max(player.duration, 1)
                )
                .progressViewStyle(.linear)
                .tint(.continuumPrimary)

                Button {
                    player.skip(by: 30)
                } label: {
                    Image(systemName: "goforward.30")
                        .frame(width: 52, height: 44)
                }
                .accessibilityLabel("Forward 30 Seconds")
            }
            .buttonStyle(.bordered)
            #else
            Slider(
                value: $displayedTime,
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        player.seek(to: displayedTime)
                    }
                }
            )
            #endif
            HStack {
                Text(PlayerTimeFormatter.formatHMS(isScrubbing ? displayedTime : player.currentTime))
                Spacer()
                Text(PlayerTimeFormatter.formatHMS(player.duration))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            displayedTime = player.currentTime
        }
        #if !os(tvOS)
        .onChange(of: player.currentTime) { _, newValue in
            guard !isScrubbing else { return }
            displayedTime = newValue
        }
        #endif
    }
}

private struct AudioPlayerOptions: View {
    let player: AudioPlayerViewModel

    private let rates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(rates, id: \.self) { rate in
                    Button("\(rate, specifier: "%.2g")x") {
                        player.setPlaybackRate(rate)
                    }
                }
            } label: {
                Label("\(player.playbackRate, specifier: "%.2g")x", systemImage: "speedometer")
                    .frame(minWidth: 92)
            }

            Menu {
                Button("Off") { player.sleepTimer.cancel() }
                Button("15 min") { player.sleepTimer.start(minutes: 15) }
                Button("30 min") { player.sleepTimer.start(minutes: 30) }
                Button("60 min") { player.sleepTimer.start(minutes: 60) }
            } label: {
                Label(
                    player.sleepTimer.isActive
                        ? PlayerTimeFormatter.formatCountdown(player.sleepTimer.remainingSeconds)
                        : "Sleep",
                    systemImage: "moon"
                )
                .frame(minWidth: 106)
            }
        }
        .buttonStyle(.bordered)
    }
}

private struct AudioChapterList: View {
    let player: AudioPlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chapters")
                .font(.headline)
            ForEach(player.chapters.sorted(by: { $0.startSeconds < $1.startSeconds })) { chapter in
                Button {
                    player.jumpToChapter(chapter)
                } label: {
                    HStack {
                        Text(chapter.title ?? "Chapter \(chapter.index + 1)")
                            .lineLimit(1)
                        Spacer()
                        Text(PlayerTimeFormatter.formatHMS(chapter.startSeconds))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding(.horizontal)
    }
}

private struct AudioCoverView: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.continuumSurface)
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "book.closed")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "book.closed")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
