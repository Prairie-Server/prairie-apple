#if os(tvOS)
import SwiftUI

/// Movie / episode detail layout for tvOS. The hero fills the top of the
/// viewport; the scrollable body underneath contains cast, a full
/// overview, and facts. Audio / subtitle track selection happens in the
/// player — the detail page only exposes a compact Version picker
/// beneath the primary actions when multiple file versions exist.
struct TVMovieDetailView: View {
    let detail: ItemDetail
    let isFavorite: Bool
    let inWatchlist: Bool
    let isWatched: Bool
    let selectedVersionFileId: Int?
    let selectedAudioTrackIndex: Int?
    let selectedSubtitleTrackIndex: Int?
    let seasons: [Season]
    let selectedSeason: Season?
    let seasonEpisodes: [EpisodeListItem]
    let isLoadingEpisodes: Bool
    let onPlay: (_ startFromBeginning: Bool) -> Void
    let onSelectVersion: (Int?) -> Void
    let onSelectAudioTrack: (Int?) -> Void
    let onSelectSubtitleTrack: (Int?) -> Void
    let onSelectSeason: (Season) -> Void
    let onToggleFavorite: () -> Void
    let onToggleWatchlist: () -> Void
    let onToggleWatched: () -> Void
    let onPersonTap: (String) -> Void
    let onNavigateToItem: (String) -> Void
    let onEpisodeTap: (String) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 48) {
                TVDetailHero(
                    title: detail.title,
                    seriesTitle: detail.type == "episode" ? detail.seriesTitle : nil,
                    logoUrl: detail.logoUrl,
                    backdropUrl: detail.backdropUrl,
                    eyebrow: detail.type == "episode" ? nil : TVHeroMetadata.eyebrow(from: detail),
                    sourceTokens: TVHeroMetadata.movieSourceTokens(from: detail),
                    ratingChip: TVHeroMetadata.contentRatingChip(from: detail),
                    overview: detail.overview,
                    factsLine: TVHeroMetadata.movieFactsLine(from: detail),
                    starringText: TVHeroMetadata.starringText(from: detail),
                    actions: { actionColumn }
                )

                VStack(alignment: .leading, spacing: 72) {
                    if showsEpisodeRail {
                        episodesSection
                    }
                    if let cast = detail.cast, !cast.isEmpty {
                        castSection(cast: cast)
                    }
                    detailsSection
                        .focusable()
                        .focusEffectDisabled()
                    aboutSection
                        .focusable()
                        .focusEffectDisabled()
                    if showsSimilarRail {
                        similarSection
                    }
                }
                .padding(.horizontal, ContinuumTheme.safePadding)
                .padding(.bottom, 160)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero actions

    @ViewBuilder
    private var actionColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            actionRow
            if availableVersions.count > 1 {
                versionPicker
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 28) {
            TVPrimaryPillButton(
                icon: "play.fill",
                title: primaryPlayLabel,
                action: { onPlay(false) }
            )

            if hasResumeProgress {
                TVSecondaryPillButton(
                    icon: "backward.end.fill",
                    title: "Start Over",
                    action: { onPlay(true) }
                )
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
                accessibilityLabel: isWatched ? watchedLabelUnmark : watchedLabelMark,
                action: onToggleWatched
            )

            if hasMoreMenu {
                moreMenu
            }
        }
    }

    // MARK: - More menu

    private var hasOverflowNavigation: Bool {
        detail.type == "episode" && detail.seriesId != nil
    }

    private var hasMoreMenu: Bool {
        hasOverflowNavigation ||
        !selectableAudioTracks.isEmpty ||
        supportsSubtitleSelection
    }

    @ViewBuilder
    private var moreMenu: some View {
        TVCircleMenuButton(accessibilityLabel: "More options") {
            if !selectableAudioTracks.isEmpty {
                Menu {
                    Button {
                        onSelectAudioTrack(nil)
                    } label: {
                        playbackMenuItem(
                            title: "Auto",
                            detail: "Use the file default track",
                            isSelected: selectedAudioTrackIndex == nil
                        )
                    }
                    ForEach(selectableAudioTracks) { track in
                        let trackIndex = track.index ?? -1
                        Button {
                            onSelectAudioTrack(track.index)
                        } label: {
                            playbackMenuItem(
                                title: audioTrackTitle(track),
                                detail: audioTrackDetail(track),
                                isSelected: selectedAudioTrackIndex == trackIndex
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
                        onSelectSubtitleTrack(nil)
                    } label: {
                        playbackMenuItem(
                            title: "Auto",
                            detail: "Use your subtitle preferences",
                            isSelected: selectedSubtitleTrackIndex == nil
                        )
                    }
                    Button {
                        onSelectSubtitleTrack(-1)
                    } label: {
                        playbackMenuItem(
                            title: "Off",
                            detail: "Start playback without subtitles",
                            isSelected: selectedSubtitleTrackIndex == -1
                        )
                    }
                    ForEach(selectableSubtitleTracks) { track in
                        let trackIndex = track.index ?? -1
                        Button {
                            onSelectSubtitleTrack(track.index)
                        } label: {
                            playbackMenuItem(
                                title: subtitleTrackTitle(track),
                                detail: subtitleTrackDetail(track),
                                isSelected: selectedSubtitleTrackIndex == trackIndex
                            )
                        }
                    }
                } label: {
                    Label("Subtitle Track", systemImage: "captions.bubble")
                }
            }

            if let seriesId = detail.seriesId,
               let seasonNumber = detail.seasonNumber,
               seasonNumber > 0 {
                Button {
                    onNavigateToItem("\(seriesId)-S\(seasonNumber)")
                } label: {
                    Label("Go to Season", systemImage: "square.stack")
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

    private var watchedLabelMark: String {
        detail.type == "episode" ? "Mark Episode Watched" : "Mark as Watched"
    }

    private var watchedLabelUnmark: String {
        detail.type == "episode" ? "Mark Episode Unwatched" : "Mark as Unwatched"
    }

    private var versionPicker: some View {
        TVVersionPillButton(currentLabel: currentVersionLabel) {
            Button {
                onSelectVersion(nil)
            } label: {
                versionMenuItem(
                    title: "Auto",
                    detail: "Best match for this device",
                    isSelected: selectedVersionFileId == nil
                )
            }
            ForEach(availableVersions) { version in
                Button {
                    onSelectVersion(version.fileId)
                } label: {
                    versionMenuItem(
                        title: versionPrimaryText(version),
                        detail: versionSecondaryText(version),
                        isSelected: selectedVersionFileId == version.fileId
                    )
                }
            }
        }
    }

    private var resumePositionSeconds: Double? {
        guard let pos = detail.userData?.positionSeconds, pos > 30 else { return nil }
        if let dur = detail.userData?.durationSeconds, dur > 0, pos >= dur - 5 {
            return nil
        }
        return pos
    }

    private var hasResumeProgress: Bool { resumePositionSeconds != nil }

    private var primaryPlayLabel: String {
        guard let pos = resumePositionSeconds else { return "Play" }
        return "Resume \(PlayerTimeFormatter.formatHMS(pos))"
    }

    // MARK: - About section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSectionHeader(label: "About", title: aboutTitle)

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

    private var aboutTitle: String {
        if detail.type == "episode" { return "Episode" }
        return "The Movie"
    }

    // MARK: - Episodes (episode detail page)

    private var showsEpisodeRail: Bool {
        detail.type == "episode" && !seasonEpisodes.isEmpty
    }

    @ViewBuilder
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSectionHeader(label: episodeRailEyebrow, title: "Episodes")
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
            } else {
                TVEpisodeRail(
                    episodes: seasonEpisodes,
                    onSelect: onEpisodeTap,
                    currentContentId: detail.contentId
                )
            }
        }
    }

    private var episodeRailEyebrow: String {
        if let seasonNumber = detail.seasonNumber, seasonNumber > 0 {
            return "Season \(seasonNumber)"
        }
        return "This Season"
    }

    // MARK: - More Like This

    /// Hide on episode pages — viewers want the next episode, not
    /// tangentially related titles. The episode rail above already
    /// serves browsing.
    private var showsSimilarRail: Bool {
        detail.type != "episode"
    }

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

    // MARK: - Details section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSectionHeader(label: "Info", title: "Details")
            TVDetailFactsSection(detail: detail)
        }
    }

    // MARK: - Version data

    private var availableVersions: [FileVersion] {
        detail.versions ?? []
    }

    private var selectedVersion: FileVersion? {
        availableVersions.first(where: { $0.fileId == selectedVersionFileId })
    }

    private var effectiveVersion: FileVersion? {
        DetailVersionSelection.displayVersion(
            versions: availableVersions,
            selectedFileId: selectedVersionFileId,
            lastFileId: detail.userData?.lastFileId,
            preferredQualityId: PlayerSettings.shared.preferredQuality
        )
    }

    private var trackSelectionVersion: FileVersion? {
        effectiveVersion
    }

    private var currentVersionLabel: String {
        versionMenuLabel(selectedVersion ?? effectiveVersion) ?? "Auto"
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

    // MARK: - Version / codec helpers

    private func normalizedVideoCodec(_ codec: String?) -> String {
        guard let codec = codec?.lowercased() else { return "H.264" }
        if codec.contains("hevc") || codec.contains("h265") { return "HEVC" }
        if codec.contains("av1") { return "AV1" }
        return "H.264"
    }

    private func normalizedAudioCodec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        if codec.contains("eac3") || codec.contains("ec-3") { return "EAC3" }
        if codec.contains("ac3") || codec.contains("ac-3") { return "AC3" }
        if codec.contains("aac") { return "AAC" }
        if codec.contains("mp3") { return "MP3" }
        return codec.uppercased()
    }

    private func versionPrimaryText(_ version: FileVersion) -> String {
        [
            version.resolution,
            normalizedVideoCodec(version.codecVideo),
            version.hdr == true ? "HDR" : nil,
            normalizedAudioCodec(version.codecAudio),
        ]
        .compactMap { $0 }
        .joined(separator: " \u{00B7} ")
    }

    private func versionMenuLabel(_ version: FileVersion?) -> String? {
        guard let version else { return nil }
        let parts = [
            version.resolution,
            version.hdr == true ? "HDR" : nil,
        ]
        .compactMap { $0 }
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }
        let codec = normalizedVideoCodec(version.codecVideo)
        if !codec.isEmpty {
            return codec
        }
        if let container = version.container?.trimmingCharacters(in: .whitespacesAndNewlines),
           !container.isEmpty {
            return container.uppercased()
        }
        return "Version \(version.fileId)"
    }

    private func versionSecondaryText(_ version: FileVersion) -> String {
        let details = [
            version.container?.uppercased(),
            version.fileSize.map(formatFileSize),
        ]
        .compactMap { $0 }
        return details.isEmpty ? "Playable" : details.joined(separator: " \u{00B7} ")
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
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
}
#endif
