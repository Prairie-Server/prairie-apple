#if os(tvOS)
import SwiftUI

/// Series detail layout for tvOS. Cinematic hero at the top; seasons +
/// a horizontal episode rail + cast + facts below.
struct TVSeriesDetailView: View {
    let detail: ItemDetail
    let isFavorite: Bool
    let inWatchlist: Bool
    let isWatched: Bool
    let seasons: [Season]
    let selectedSeason: Season?
    let episodes: [EpisodeListItem]
    let isLoadingEpisodes: Bool
    let selectedNextUpFileId: Int?
    let nextUpPlaybackDetail: ItemDetail?
    let isLoadingNextUpPlaybackDetail: Bool
    let didLoadNextUpPlaybackDetail: Bool
    let onSelectSeason: (Season) -> Void
    let onPlayEpisode: (_ contentId: String, _ fileId: Int?, _ startFromBeginning: Bool) -> Void
    let onEpisodeTap: (_ contentId: String) -> Void
    let onSelectNextUpVersion: (Int?) -> Void
    let onToggleFavorite: () -> Void
    let onToggleWatchlist: () -> Void
    let onToggleWatched: () -> Void
    let onPersonTap: (String) -> Void
    let onNavigateToItem: (String) -> Void

    @Namespace private var detailFocusNamespace

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 48) {
                TVDetailHero(
                    title: detail.title,
                    seriesTitle: nil,
                    logoUrl: detail.logoUrl,
                    backdropUrl: detail.backdropUrl,
                    eyebrow: TVHeroMetadata.eyebrow(from: detail),
                    sourceTokens: TVHeroMetadata.seriesSourceTokens(from: detail),
                    ratingChip: TVHeroMetadata.contentRatingChip(from: detail),
                    overview: detail.overview,
                    factsLine: TVHeroMetadata.seriesFactsLine(from: detail),
                    starringText: TVHeroMetadata.starringText(from: detail),
                    actions: { actionColumn }
                )

                VStack(alignment: .leading, spacing: 72) {
                    episodeSection
                    if let cast = detail.cast, !cast.isEmpty {
                        castSection(cast: cast)
                    }
                    detailsSection
                        .readableFocusSection()
                    aboutSection
                        .readableFocusSection()
                    similarSection
                }
                .padding(.horizontal, ContinuumTheme.safePadding)
                .padding(.bottom, 160)
            }
        }
        .ignoresSafeArea()
        .focusScope(detailFocusNamespace)
    }

    // MARK: - Hero actions

    @ViewBuilder
    private var actionColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            actionRow
            if shouldShowVersionPlaceholder {
                TVVersionPillPlaceholder()
            } else if nextUpEpisode != nil, nextUpVersionRows.count > 1 {
                nextUpVersionPicker
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 28) {
            if let nextUp = nextUpEpisode {
                TVPrimaryPillButton(
                    icon: "play.fill",
                    title: playButtonLabel(for: nextUp),
                    action: { onPlayEpisode(nextUp.contentId, selectedFileId(for: nextUp), false) },
                    prefersDefaultFocus: true,
                    defaultFocusNamespace: detailFocusNamespace
                )
                if nextUp.userData?.isInProgress == true {
                    TVSecondaryPillButton(
                        icon: "backward.end.fill",
                        title: "Start Over",
                        action: { onPlayEpisode(nextUp.contentId, selectedFileId(for: nextUp), true) }
                    )
                }
            }

            TVCircleActionButton(
                icon: "heart",
                iconActive: "heart.fill",
                isActive: isFavorite,
                accessibilityLabel: isFavorite ? "Remove from favorites" : "Add to favorites",
                action: onToggleFavorite
            )

            TVCircleActionButton(
                icon: "bookmark",
                iconActive: "bookmark.fill",
                isActive: inWatchlist,
                accessibilityLabel: inWatchlist ? "Remove from watchlist" : "Add to watchlist",
                action: onToggleWatchlist
            )

            TVCircleActionButton(
                icon: "checkmark.circle",
                iconActive: "checkmark.circle.fill",
                isActive: isWatched,
                accessibilityLabel: isWatched ? "Mark Series Unwatched" : "Mark Series Watched",
                action: onToggleWatched
            )
        }
    }

    /// Best "Play" target for the series: an in-progress episode if there
    /// is one, otherwise the first unwatched in the selected season, else
    /// the first episode we loaded.
    private var nextUpEpisode: EpisodeListItem? {
        if let inProgress = episodes.first(where: { $0.userData?.isInProgress == true }) {
            return inProgress
        }
        if let unwatched = episodes.first(where: { !($0.userData?.played ?? false) }) {
            return unwatched
        }
        return episodes.first
    }

    private func playButtonLabel(for episode: EpisodeListItem) -> String {
        if episode.userData?.isInProgress == true {
            return "Resume S\(episode.seasonNumber) · E\(episode.episodeNumber)"
        }
        return "Play S\(episode.seasonNumber) · E\(episode.episodeNumber)"
    }

    // MARK: - Next-up version picker

    private var shouldShowVersionPlaceholder: Bool {
        nextUpEpisode != nil
            && (isLoadingNextUpPlaybackDetail || (!didLoadNextUpPlaybackDetail && nextUpPlaybackDetail == nil))
    }

    private var nextUpVersionPicker: some View {
        TVVersionPillButton(currentLabel: currentVersionLabel) {
            Button {
                onSelectNextUpVersion(nil)
            } label: {
                versionMenuItem(
                    title: "Auto",
                    detail: "Best match for this device",
                    isSelected: selectedNextUpFileId == nil
                )
            }
            ForEach(nextUpVersionRows) { row in
                Button {
                    onSelectNextUpVersion(row.fileId)
                } label: {
                    versionMenuItem(
                        title: row.title,
                        detail: row.detail,
                        isSelected: selectedNextUpFileId == row.fileId
                    )
                }
            }
        }
    }

    private func selectedFileId(for episode: EpisodeListItem) -> Int? {
        guard let selectedNextUpFileId else { return nil }
        if let versions = nextUpPlaybackDetail?.versions, !versions.isEmpty {
            return versions.contains(where: { $0.fileId == selectedNextUpFileId })
                ? selectedNextUpFileId
                : nil
        }
        guard (episode.files ?? []).contains(where: { $0.fileId == selectedNextUpFileId }) else { return nil }
        return selectedNextUpFileId
    }

    private var currentVersionLabel: String {
        if let effectiveNextUpVersion {
            return versionMenuLabel(effectiveNextUpVersion)
        }
        guard let nextUp = nextUpEpisode else { return "Auto" }
        let files = nextUp.files ?? []
        let effective = files.first(where: { $0.fileId == selectedNextUpFileId }) ?? files.first
        guard let file = effective else { return "Auto" }
        return episodeFileLabel(file)
    }

    private var effectiveNextUpVersion: FileVersion? {
        DetailVersionSelection.displayVersion(
            versions: nextUpPlaybackDetail?.versions ?? [],
            selectedFileId: selectedNextUpFileId,
            lastFileId: nextUpPlaybackDetail?.userData?.lastFileId,
            preferredQualityId: PlayerSettings.shared.preferredQuality
        )
    }

    private var nextUpVersionRows: [TVSeriesNextUpVersionRow] {
        if let versions = nextUpPlaybackDetail?.versions, !versions.isEmpty {
            return versions.map { version in
                TVSeriesNextUpVersionRow(
                    fileId: version.fileId,
                    title: versionTitle(version),
                    detail: versionDetail(version)
                )
            }
        }
        guard let files = nextUpEpisode?.files, !files.isEmpty else { return [] }
        return files.map { file in
            TVSeriesNextUpVersionRow(
                fileId: file.fileId,
                title: episodeFileTitle(file),
                detail: episodeFileDetail(file)
            )
        }
    }

    // MARK: - Episodes + season selector

    @ViewBuilder
    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            episodeSectionHeader
            if seasons.count > 1 {
                seasonRow
            }
            episodeBody
        }
    }

    private var episodeSectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            TVSectionHeader(
                label: selectedSeason.map { "Season \($0.seasonNumber)" } ?? "Episodes",
                title: "Episodes"
            )
            Spacer()
            if let count = selectedSeason?.episodeCount, count > 0 {
                Text("\(count) episode\(count == 1 ? "" : "s")")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.continuumSecondaryText)
            }
        }
    }

    private var seasonRow: some View {
        TVSeasonChipRow(
            seasons: seasons,
            selectedSeasonId: selectedSeason?.id,
            onSelect: onSelectSeason
        )
    }

    @ViewBuilder
    private var episodeBody: some View {
        if selectedSeason == nil && seasons.isEmpty {
            EmptyView()
        } else if isLoadingEpisodes {
            HStack {
                Spacer()
                ProgressView().tint(.continuumOnSurface).padding()
                Spacer()
            }
        } else if episodes.isEmpty {
            Text("No episodes available")
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(.continuumSecondaryText)
        } else {
            TVEpisodeRail(
                episodes: episodes,
                onSelect: onEpisodeTap
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSectionHeader(label: "About", title: "The Series")

            if let tagline = detail.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(.continuumOnSurface.opacity(0.85))
                    .frame(maxWidth: 1400, alignment: .leading)
            }

            if let overview = detail.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(.continuumOnSurface.opacity(0.82))
                    .lineSpacing(9)
                    .frame(maxWidth: 1400, alignment: .leading)
            }
        }
    }

    // MARK: - More Like This

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSectionHeader(label: "Recommended", title: "More Like This")
            TVSimilarRail(
                contentId: detail.contentId,
                onSelect: onNavigateToItem
            )
        }
    }

    // MARK: - Cast

    @ViewBuilder
    private func castSection(cast: [CastMember]) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSectionHeader(label: "Cast", title: "& Crew")
            TVDetailCastRail(cast: cast, onTap: onPersonTap)
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSectionHeader(label: "Info", title: "Details")
            TVDetailFactsSection(detail: detail)
        }
    }

    private func versionTitle(_ version: FileVersion) -> String {
        let parts = [
            version.resolution,
            normalizedVideoCodec(version.codecVideo),
            version.hdr == true ? "HDR" : nil,
            normalizedAudioCodec(version.codecAudio),
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: " \u{00B7} ")
        }
        return versionMenuLabel(version)
    }

    private func versionMenuLabel(_ version: FileVersion?) -> String {
        guard let version else { return "Auto" }
        let parts = [
            version.resolution,
            version.hdr == true ? "HDR" : nil,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }
        if let codec = normalizedVideoCodec(version.codecVideo), !codec.isEmpty {
            return codec
        }
        if let container = version.container?.trimmingCharacters(in: .whitespacesAndNewlines),
           !container.isEmpty {
            return container.uppercased()
        }
        return "Version \(version.fileId)"
    }

    private func versionDetail(_ version: FileVersion) -> String? {
        let parts = [
            version.container?.uppercased(),
            version.fileSize.map(formatFileSize),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func episodeFileLabel(_ file: EpisodeFile) -> String {
        let parts = [
            file.resolution,
            file.hdr == true ? "HDR" : nil,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }
        if let codec = normalizedVideoCodec(file.codecVideo), !codec.isEmpty {
            return codec
        }
        if let container = file.container?.trimmingCharacters(in: .whitespacesAndNewlines),
           !container.isEmpty {
            return container.uppercased()
        }
        return "Version \(file.fileId)"
    }

    private func episodeFileTitle(_ file: EpisodeFile) -> String {
        let parts = [
            file.resolution,
            normalizedVideoCodec(file.codecVideo),
            file.hdr == true ? "HDR" : nil,
            file.audioChannels.map { "\($0)ch" }
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: " \u{00B7} ")
        }
        return episodeFileLabel(file)
    }

    private func episodeFileDetail(_ file: EpisodeFile) -> String? {
        let parts = [
            file.container?.uppercased(),
            file.fileSize.map(formatFileSize),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func normalizedVideoCodec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        if codec.contains("hevc") || codec.contains("h265") { return "HEVC" }
        if codec.contains("av1") { return "AV1" }
        if codec.contains("avc") || codec.contains("h264") { return "H.264" }
        return codec.uppercased()
    }

    private func normalizedAudioCodec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        if codec.contains("eac3") || codec.contains("ec-3") { return "EAC3" }
        if codec.contains("ac3") || codec.contains("ac-3") { return "AC3" }
        if codec.contains("aac") { return "AAC" }
        if codec.contains("mp3") { return "MP3" }
        return codec.uppercased()
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }

    @ViewBuilder
    private func versionMenuItem(title: String, detail: String?, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.continuumPrimary)
                }
                Text(title)
                    .font(.continuumBody)
                    .foregroundColor(.continuumOnSurface)
                    .lineLimit(2)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.continuumCaption)
                    .foregroundColor(.continuumSecondaryText)
                    .lineLimit(2)
            }
        }
    }
}

private struct TVSeriesNextUpVersionRow: Identifiable, Hashable {
    let fileId: Int
    let title: String
    let detail: String?

    var id: Int { fileId }
}

#endif
