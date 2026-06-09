import SwiftUI

/// Detail screen that routes to the appropriate Movie / Series /
/// Season / Episode layout for the current platform. Phones get the
/// `MovieDetailContent` / `SeriesDetailContent` / `SeasonDetailContent`
/// stack; tvOS forwards to `TVItemDetailView` for the cinematic
/// 10-foot layout.
struct ItemDetailView: View {
    let contentId: String

    var body: some View {
        #if os(tvOS)
        TVItemDetailView(contentId: contentId)
        #else
        ItemDetailPhoneContent(contentId: contentId)
        #endif
    }
}

#if !os(tvOS)
private struct ItemDetailPhoneContent: View {
    let contentId: String

    @State private var viewModel = ItemDetailViewModel()
    @State private var preferredVersionFileId: Int?
    @State private var preferredNextUpFileId: Int?
    @State private var nextUpWatchDetail: WatchDetail?
    @State private var refreshOnPlayerDismiss = false
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let detail = viewModel.detail {
                content(for: detail)
            } else if let error = viewModel.error {
                ErrorView(state: error, onRetry: { Task { await viewModel.loadDetail(contentId: contentId) } })
            } else {
                Color.clear
            }
        }
        .continuumBackground()
        .continuumNavigationTitleDisplayMode(.inline)
        .continuumNavigationBarBackgroundHidden()
        .task(id: contentId) {
            preferredVersionFileId = nil
            preferredNextUpFileId = nil
            nextUpWatchDetail = nil
            refreshOnPlayerDismiss = false
            await viewModel.loadDetail(contentId: contentId)
        }
        .onChange(of: router.presentedPlayer?.id) { oldValue, newValue in
            guard oldValue != nil, newValue == nil, refreshOnPlayerDismiss else { return }
            refreshOnPlayerDismiss = false
            Task { await viewModel.loadDetail(contentId: contentId) }
        }
    }

    @ViewBuilder
    private func content(for detail: ItemDetail) -> some View {
        if detail.isAudiobook {
            AudiobookDetailContent(
                detail: detail,
                onNavigateToItem: { id in
                    router.navigate(to: .itemDetail(contentId: id))
                }
            )
        } else if detail.type == "season" {
            SeasonDetailContent(
                detail: detail,
                isFavorite: viewModel.isFavorite,
                inWatchlist: viewModel.inWatchlist,
                isWatched: viewModel.isWatched,
                seasons: viewModel.seasons,
                selectedSeason: viewModel.selectedSeason,
                episodes: viewModel.episodes,
                isLoadingEpisodes: viewModel.isLoadingEpisodes,
                selectedNextUpFileId: preferredNextUpFileId,
                nextUpWatchDetail: nextUpWatchDetail,
                onPlayEpisode: { id, fileId, startFromBeginning in
                    let episode = viewModel.episodes.first { $0.contentId == id }
                    let resumePosition = startFromBeginning
                        ? nil
                        : playableResumePosition(
                            position: episode?.userData?.positionSeconds,
                            duration: episode?.userData?.durationSeconds
                        )
                    if let fileId {
                        presentPlayerFromDetail(
                            contentId: id,
                            fileId: fileId,
                            startFromBeginning: startFromBeginning,
                            resumePosition: resumePosition
                        )
                    } else {
                        presentPlayerFromDetail(
                            contentId: id,
                            startFromBeginning: startFromBeginning,
                            resumePosition: resumePosition
                        )
                    }
                },
                onEpisodeTap: { id in
                    router.navigate(to: .itemDetail(contentId: id))
                },
                onSelectSeason: { season in
                    guard season.id != detail.contentId else { return }
                    router.navigate(to: .itemDetail(contentId: season.contentId))
                },
                onSelectNextUpVersion: { fileId in
                    preferredNextUpFileId = fileId
                },
                onToggleFavorite: { Task { await viewModel.toggleFavorite() } },
                onToggleWatchlist: { Task { await viewModel.toggleWatchlist() } },
                onToggleWatched: { Task { await viewModel.toggleWatched() } },
                onPersonTap: { personId in
                    if let pid = Int(personId) {
                        router.navigate(to: .personDetail(personId: pid))
                    }
                },
                onNavigateToItem: { id in
                    router.navigate(to: .itemDetail(contentId: id))
                }
            )
            .task(id: nextUpEpisodeContentId(for: detail)) {
                await loadNextUpWatchDetail(for: detail)
            }
        } else if detail.type == "series" {
            SeriesDetailContent(
                detail: detail,
                isFavorite: viewModel.isFavorite,
                inWatchlist: viewModel.inWatchlist,
                isWatched: viewModel.isWatched,
                seasons: viewModel.seasons,
                selectedSeason: viewModel.selectedSeason,
                episodes: viewModel.episodes,
                isLoadingEpisodes: viewModel.isLoadingEpisodes,
                selectedNextUpFileId: preferredNextUpFileId,
                nextUpWatchDetail: nextUpWatchDetail,
                onSelectSeason: { season in
                    Task { await viewModel.selectSeason(season) }
                },
                onPlayEpisode: { id, fileId, startFromBeginning in
                    presentPlayerFromDetail(
                        contentId: id,
                        fileId: fileId,
                        startFromBeginning: startFromBeginning,
                        resumePosition: startFromBeginning
                            ? nil
                            : viewModel.episodes.first(where: { $0.contentId == id })?.userData?.positionSeconds
                    )
                },
                onEpisodeTap: { id in
                    router.navigate(to: .itemDetail(contentId: id))
                },
                onSelectNextUpVersion: { fileId in
                    preferredNextUpFileId = fileId
                },
                onToggleFavorite: { Task { await viewModel.toggleFavorite() } },
                onToggleWatchlist: { Task { await viewModel.toggleWatchlist() } },
                onToggleWatched: { Task { await viewModel.toggleWatched() } },
                onPersonTap: { personId in
                    if let pid = Int(personId) {
                        router.navigate(to: .personDetail(personId: pid))
                    }
                },
                onNavigateToItem: { id in
                    router.navigate(to: .itemDetail(contentId: id))
                }
            )
            .task(id: nextUpEpisodeContentId(for: detail)) {
                await loadNextUpWatchDetail(for: detail)
            }
        } else {
            MovieDetailContent(
                detail: detail,
                isFavorite: viewModel.isFavorite,
                inWatchlist: viewModel.inWatchlist,
                isWatched: viewModel.isWatched,
                selectedVersionFileId: preferredVersionFileId,
                seasons: viewModel.seasons,
                selectedSeason: viewModel.selectedSeason,
                seasonEpisodes: viewModel.episodes,
                isLoadingEpisodes: viewModel.isLoadingEpisodes,
                onPlay: { startFromBeginning in
                    let resumePosition = startFromBeginning ? nil : playableResumePosition(for: detail)
                    if let fileId = playbackFileId(for: detail) {
                        presentPlayerFromDetail(
                            contentId: contentId,
                            fileId: fileId,
                            startFromBeginning: startFromBeginning,
                            resumePosition: resumePosition
                        )
                    } else {
                        presentPlayerFromDetail(
                            contentId: contentId,
                            startFromBeginning: startFromBeginning,
                            resumePosition: resumePosition
                        )
                    }
                },
                onSelectVersion: { fileId in
                    preferredVersionFileId = fileId
                },
                onSelectSeason: { season in
                    guard season.id != detail.contentId else { return }
                    router.navigate(to: .itemDetail(contentId: season.contentId))
                },
                onToggleFavorite: { Task { await viewModel.toggleFavorite() } },
                onToggleWatchlist: { Task { await viewModel.toggleWatchlist() } },
                onToggleWatched: { Task { await viewModel.toggleWatched() } },
                onPersonTap: { personId in
                    if let pid = Int(personId) {
                        router.navigate(to: .personDetail(personId: pid))
                    }
                },
                onNavigateToItem: { id in
                    router.navigate(to: .itemDetail(contentId: id))
                },
                onEpisodeTap: { id in
                    router.navigate(to: .itemDetail(contentId: id))
                }
            )
        }
    }

    private func playbackFileId(for detail: ItemDetail) -> Int? {
        preferredVersionFileId
    }

    private func playableResumePosition(for detail: ItemDetail) -> Double? {
        playableResumePosition(
            position: detail.userData?.positionSeconds,
            duration: detail.userData?.durationSeconds
        )
    }

    private func playableResumePosition(position: Double?, duration: Double?) -> Double? {
        guard let position, position.isFinite, position > 30 else { return nil }
        if let duration, duration.isFinite, duration > 0, position >= duration - 5 {
            return nil
        }
        return position
    }

    private func nextUpEpisode(for detail: ItemDetail) -> EpisodeListItem? {
        guard detail.type == "series" || detail.type == "season" else { return nil }
        if let inProgress = viewModel.episodes.first(where: { $0.userData?.isInProgress == true }) {
            return inProgress
        }
        if let unwatched = viewModel.episodes.first(where: { !($0.userData?.played ?? false) }) {
            return unwatched
        }
        return viewModel.episodes.first
    }

    private func nextUpEpisodeContentId(for detail: ItemDetail) -> String? {
        nextUpEpisode(for: detail)?.contentId
    }

    private func loadNextUpWatchDetail(for detail: ItemDetail) async {
        guard let nextUp = nextUpEpisode(for: detail) else {
            nextUpWatchDetail = nil
            preferredNextUpFileId = nil
            return
        }

        nextUpWatchDetail = nil
        preferredNextUpFileId = nil

        do {
            let watchDetail = try await ContinuumAPI.shared.watchDetail(contentId: nextUp.contentId)
            guard !Task.isCancelled else { return }
            nextUpWatchDetail = watchDetail
        } catch {
            guard !Task.isCancelled else { return }
            nextUpWatchDetail = nil
        }
    }

    private func presentPlayerFromDetail(
        contentId: String,
        fileId: Int? = nil,
        audioTrackIndex: Int? = nil,
        subtitleTrackIndex: Int? = nil,
        startFromBeginning: Bool,
        resumePosition: Double?
    ) {
        refreshOnPlayerDismiss = true
        // Pass the artwork URLs we already loaded into the detail view so
        // PlayerViewModel.pushNowPlayingArtwork can publish lock-screen art
        // without re-fetching the catalog item. The hints are best-effort —
        // when the play target differs from the visible detail (e.g. a
        // related episode tap), the player falls back to its own fetch.
        let isOwnDetail = viewModel.detail?.contentId == contentId
        router.presentPlayer(
            contentId: contentId,
            fileId: fileId,
            audioTrackIndex: audioTrackIndex,
            subtitleTrackIndex: subtitleTrackIndex,
            startFromBeginning: startFromBeginning,
            resumePosition: resumePosition,
            posterURL: isOwnDetail ? viewModel.detail?.posterUrl : nil,
            backdropURL: isOwnDetail ? viewModel.detail?.backdropUrl : nil
        )
    }
}
#endif
