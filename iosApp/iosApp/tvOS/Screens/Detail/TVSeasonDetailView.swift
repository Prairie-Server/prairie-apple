#if os(tvOS)
import SwiftUI

/// Season detail layout for tvOS. Scoped to a single season of a series:
/// the hero's eyebrow carries the parent-series title, the title line is
/// the season's own ("Season 2" / "Specials"), and the below-fold body
/// shows just this season's episode rail plus cast, details, and about.
///
/// Play button targets the next-up episode *within this season* (resume
/// if an episode is in progress, otherwise the first unwatched one).
/// Mark Watched targets the season, which the server fans out to every
/// leaf episode.
struct TVSeasonDetailView: View {
    let detail: ItemDetail
    let isFavorite: Bool
    let inWatchlist: Bool
    let isWatched: Bool
    let seasons: [Season]
    let selectedSeason: Season?
    let episodes: [EpisodeListItem]
    let isLoadingEpisodes: Bool
    let selectedNextUpFileId: Int?
    let selectedNextUpAudioTrackIndex: Int?
    let selectedNextUpSubtitleTrackIndex: Int?
    let nextUpPlaybackDetail: ItemDetail?
    let onPlayEpisode: (_ contentId: String, _ fileId: Int?, _ startFromBeginning: Bool) -> Void
    let onEpisodeTap: (_ contentId: String) -> Void
    let onSelectSeason: (Season) -> Void
    let onSelectNextUpVersion: (Int?) -> Void
    let onSelectNextUpAudioTrack: (Int?) -> Void
    let onSelectNextUpSubtitleTrack: (Int?) -> Void
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
                    logoUrl: nil,
                    backdropUrl: detail.backdropUrl,
                    eyebrow: detail.seriesTitle,
                    sourceTokens: sourceTokens,
                    ratingChip: nil,
                    overview: detail.overview,
                    factsLine: [],
                    starringText: TVHeroMetadata.starringText(from: detail),
                    actions: { actionColumn }
                )

                VStack(alignment: .leading, spacing: 72) {
                    episodeSection
                    if let cast = detail.cast, !cast.isEmpty {
                        castSection(cast: cast)
                    }
                    detailsSection
                        .focusable()
                        .focusEffectDisabled()
                    if detail.overview?.isEmpty == false {
                        aboutSection
                            .focusable()
                            .focusEffectDisabled()
                    }
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
            if let nextUp = nextUpEpisode,
               (nextUp.files?.count ?? 0) > 1 {
                nextUpVersionPicker(for: nextUp)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 28) {
            if let nextUp = nextUpEpisode {
                TVPrimaryPillButton(
                    icon: "play.fill",
                    title: playButtonLabel(for: nextUp),
                    action: { onPlayEpisode(nextUp.contentId, selectedNextUpFileId, false) },
                    prefersDefaultFocus: true,
                    defaultFocusNamespace: detailFocusNamespace
                )
                if nextUp.userData?.isInProgress == true {
                    TVSecondaryPillButton(
                        icon: "backward.end.fill",
                        title: "Start Over",
                        action: { onPlayEpisode(nextUp.contentId, selectedNextUpFileId, true) }
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
                accessibilityLabel: isWatched ? "Mark Season Unwatched" : "Mark Season Watched",
                action: onToggleWatched
            )

            if hasMoreMenu {
                moreMenu
            }
        }
    }

    private var hasMoreMenu: Bool {
        detail.seriesId != nil || !selectableAudioTracks.isEmpty || supportsSubtitleSelection
    }

    @ViewBuilder
    private var moreMenu: some View {
        TVCircleMenuButton(accessibilityLabel: "More options") {
            if !selectableAudioTracks.isEmpty {
                Menu {
                    Button {
                        onSelectNextUpAudioTrack(nil)
                    } label: {
                        playbackMenuItem(
                            title: "Auto",
                            detail: "Use the file default track",
                            isSelected: selectedNextUpAudioTrackIndex == nil
                        )
                    }
                    ForEach(selectableAudioTracks) { track in
                        let trackIndex = track.index ?? -1
                        Button {
                            onSelectNextUpAudioTrack(track.index)
                        } label: {
                            playbackMenuItem(
                                title: audioTrackTitle(track),
                                detail: audioTrackDetail(track),
                                isSelected: selectedNextUpAudioTrackIndex == trackIndex
                            )
                        }
                    }
                } label: {
                    Label("Audio Track", systemImage: "speaker.wave.2")
                }
            }

            if supportsSubtitleSelection {
                Menu {
                    Button {
                        onSelectNextUpSubtitleTrack(nil)
                    } label: {
                        playbackMenuItem(
                            title: "Auto",
                            detail: "Use your subtitle preferences",
                            isSelected: selectedNextUpSubtitleTrackIndex == nil
                        )
                    }
                    Button {
                        onSelectNextUpSubtitleTrack(-1)
                    } label: {
                        playbackMenuItem(
                            title: "Off",
                            detail: "Start playback without subtitles",
                            isSelected: selectedNextUpSubtitleTrackIndex == -1
                        )
                    }
                    ForEach(selectableSubtitleTracks) { track in
                        let trackIndex = track.index ?? -1
                        Button {
                            onSelectNextUpSubtitleTrack(track.index)
                        } label: {
                            playbackMenuItem(
                                title: subtitleTrackTitle(track),
                                detail: subtitleTrackDetail(track),
                                isSelected: selectedNextUpSubtitleTrackIndex == trackIndex
                            )
                        }
                    }
                } label: {
                    Label("Subtitle Track", systemImage: "captions.bubble")
                }
            }

            if let seriesId = detail.seriesId {
                Button {
                    onNavigateToItem(seriesId)
                } label: {
                    Label("Go to Series", systemImage: "tv")
                }
            }
        }
    }

    // MARK: - Next-up version picker

    @ViewBuilder
    private func nextUpVersionPicker(for episode: EpisodeListItem) -> some View {
        let files = episode.files ?? []
        TVVersionPillButton(currentLabel: currentVersionLabel(for: episode)) {
            Button {
                onSelectNextUpVersion(nil)
            } label: {
                versionMenuItem(
                    title: "Auto",
                    detail: "Best match for this device",
                    isSelected: selectedNextUpFileId == nil
                )
            }
            ForEach(files, id: \.fileId) { file in
                Button {
                    onSelectNextUpVersion(file.fileId)
                } label: {
                    versionMenuItem(
                        title: episodeFileTitle(file),
                        detail: episodeFileDetail(file),
                        isSelected: selectedNextUpFileId == file.fileId
                    )
                }
            }
        }
    }

    private func currentVersionLabel(for episode: EpisodeListItem) -> String {
        let files = episode.files ?? []
        let effective = files.first(where: { $0.fileId == selectedNextUpFileId }) ?? files.first
        guard let file = effective else { return "Auto" }
        let parts = [
            file.resolution,
            file.hdr == true ? "HDR" : nil,
        ].compactMap { $0 }
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
        .compactMap { $0 }
        if !parts.isEmpty {
            return parts.joined(separator: " \u{00B7} ")
        }
        if let container = file.container?.trimmingCharacters(in: .whitespacesAndNewlines),
           !container.isEmpty {
            return container.uppercased()
        }
        return "Version \(file.fileId)"
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

    @ViewBuilder
    private func playbackMenuItem(title: String, detail: String?, isSelected: Bool) -> some View {
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
            return "Resume E\(episode.episodeNumber)"
        }
        return "Play E\(episode.episodeNumber)"
    }

    private var effectiveNextUpVersion: FileVersion? {
        let versions = nextUpPlaybackDetail?.versions ?? []
        if let selectedNextUpFileId,
           let selected = versions.first(where: { $0.fileId == selectedNextUpFileId }) {
            return selected
        }
        if let lastFileId = nextUpPlaybackDetail?.userData?.lastFileId,
           let lastVersion = versions.first(where: { $0.fileId == lastFileId }) {
            return lastVersion
        }
        return versions.first
    }

    private var trackSelectionVersion: FileVersion? {
        effectiveNextUpVersion
    }

    private var selectableAudioTracks: [AudioTrack] {
        trackSelectionVersion?.audioTracks?.filter { $0.index != nil } ?? []
    }

    private var selectableSubtitleTracks: [SubtitleTrack] {
        trackSelectionVersion?.subtitleTracks?.filter { $0.index != nil } ?? []
    }

    private var supportsSubtitleSelection: Bool {
        trackSelectionVersion != nil
    }

    private func audioTrackTitle(_ track: AudioTrack) -> String {
        if let title = normalizedTrackText(track.title) { return title }
        if let language = localizedLanguageName(track.language) { return language }
        if let index = track.index { return "Track \(index)" }
        return "Audio Track"
    }

    private func audioTrackDetail(_ track: AudioTrack) -> String? {
        var parts: [String] = []
        if let language = localizedLanguageName(track.language),
           let title = normalizedTrackText(track.title),
           !title.localizedCaseInsensitiveContains(language) {
            parts.append(language)
        }
        if let layout = normalizedAudioLayout(track), !layout.isEmpty {
            parts.append(layout)
        }
        if let codec = normalizedAudioCodec(track.codec) {
            parts.append(codec)
        }
        if track.isDefault == true {
            parts.append("Default")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func subtitleTrackTitle(_ track: SubtitleTrack) -> String {
        if let title = normalizedTrackText(track.title) { return title }
        if let language = localizedLanguageName(track.language) { return language }
        if let index = track.index { return "Track \(index)" }
        return "Subtitle Track"
    }

    private func subtitleTrackDetail(_ track: SubtitleTrack) -> String? {
        var parts: [String] = []
        if let language = localizedLanguageName(track.language),
           let title = normalizedTrackText(track.title),
           !title.localizedCaseInsensitiveContains(language) {
            parts.append(language)
        }
        if let codec = track.codec?.uppercased(), !codec.isEmpty {
            parts.append(codec)
        }
        if track.forced == true {
            parts.append("Forced")
        }
        if track.isDefault == true {
            parts.append("Default")
        }
        if track.external == true {
            parts.append("External")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func normalizedTrackText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func localizedLanguageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)?.capitalized
            ?? code.uppercased()
    }

    private func normalizedAudioLayout(_ track: AudioTrack) -> String? {
        if let layout = track.channelLayout?.lowercased(), !layout.isEmpty {
            if layout.contains("7.1") { return "7.1" }
            if layout.contains("5.1") { return "5.1" }
            if layout.contains("stereo") || layout == "2.0" { return "Stereo" }
            return track.channelLayout
        }
        if let channels = track.channels {
            switch channels {
            case 1: return "Mono"
            case 2: return "Stereo"
            case 6: return "5.1"
            case 8: return "7.1"
            default: return "\(channels)ch"
            }
        }
        return nil
    }

    private func normalizedAudioCodec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        if codec.contains("eac3") || codec.contains("ec-3") { return "EAC3" }
        if codec.contains("ac3") || codec.contains("ac-3") { return "AC3" }
        if codec.contains("aac") { return "AAC" }
        if codec.contains("mp3") { return "MP3" }
        return codec.uppercased()
    }

    // MARK: - Source row tokens

    private var sourceTokens: [String] {
        var tokens: [String] = []
        if let count = detail.episodeCount, count > 0 {
            tokens.append("\(count) Episode\(count == 1 ? "" : "s")")
        } else if !episodes.isEmpty {
            tokens.append("\(episodes.count) Episode\(episodes.count == 1 ? "" : "s")")
        }
        if let genres = detail.genres, !genres.isEmpty {
            tokens.append(contentsOf: genres.prefix(2))
        }
        return tokens
    }

    // MARK: - Episodes

    @ViewBuilder
    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSectionHeader(label: "This Season", title: "Episodes")
            if seasons.count > 1 {
                TVSeasonChipRow(
                    seasons: seasons,
                    selectedSeasonId: selectedSeason?.id,
                    onSelect: onSelectSeason
                )
            }
            if isLoadingEpisodes {
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
                TVEpisodeRail(episodes: episodes, onSelect: onEpisodeTap)
            }
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

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSectionHeader(label: "About", title: detail.title)

            if let overview = detail.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(.continuumOnSurface.opacity(0.82))
                    .lineSpacing(9)
                    .frame(maxWidth: 1400, alignment: .leading)
            }
        }
    }
}
#endif
