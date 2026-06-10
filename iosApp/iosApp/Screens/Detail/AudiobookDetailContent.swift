import SwiftUI

struct AudiobookDetailContent: View {
    let detail: ItemDetail
    let onNavigateToItem: (String) -> Void

    @Environment(AudioPlaybackStore.self) private var audioStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                header

                if let overview = detail.overview, !overview.isEmpty {
                    detailSection(title: "About") {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                }

                if !parts.isEmpty {
                    detailSection(title: "Parts") {
                        VStack(spacing: 10) {
                            ForEach(parts.indices, id: \.self) { index in
                                partRow(part: parts[index], fallbackIndex: index)
                            }
                        }
                    }
                }

                if !displayChapters.isEmpty {
                    detailSection(title: "Chapters") {
                        VStack(spacing: 10) {
                            ForEach(displayChapters) { chapter in
                                chapterRow(chapter)
                            }
                        }
                    }
                }

                if let series = detail.audiobook?.series, !series.entries.isEmpty {
                    detailSection(title: series.name ?? "Series") {
                        relatedRail(items: series.entries)
                    }
                }

                if !otherNarrations.isEmpty {
                    detailSection(title: "Alternate Narrations") {
                        VStack(spacing: 10) {
                            ForEach(otherNarrations) { narration in
                                Button {
                                    onNavigateToItem(narration.contentId)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.wave.2")
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(narration.title)
                                                .font(.headline)
                                                .lineLimit(1)
                                            if !narration.narrators.isEmpty {
                                                Text(narration.narrators.joined(separator: ", "))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let related = detail.audiobook?.related {
                    if !related.alsoByAuthor.isEmpty {
                        detailSection(title: "More by Author") {
                            relatedRail(items: related.alsoByAuthor)
                        }
                    }
                    if !related.similar.isEmpty {
                        detailSection(title: "Related") {
                            relatedRail(items: related.similar)
                        }
                    }
                }

            }
            .padding(.horizontal, ContinuumTheme.safePadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
        .continuumBackground()
    }

    @ViewBuilder
    private var header: some View {
        #if os(tvOS)
        HStack(alignment: .top, spacing: 48) {
            cover(size: coverSize)
            headerText
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.top, 24)
            Spacer(minLength: 0)
        }
        .padding(.top, 120)
        #else
        VStack(spacing: 22) {
            cover(size: coverSize)
            headerText
                .frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity)
        #endif
    }

    private var headerText: some View {
        VStack(alignment: headerAlignment, spacing: 14) {
            Text(detail.title)
                .font(titleFont)
                .fontWeight(.bold)
                .multilineTextAlignment(headerTextAlignment)
                .foregroundColor(.continuumOnSurface)

            if !metadataLine.isEmpty {
                Text(metadataLine)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(headerTextAlignment)
            }

            if let publisher = detail.audiobook?.publisher, !publisher.isEmpty {
                Text(publisher)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            actionRow
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        #if os(tvOS)
        // The hero pills own their focus appearance — system bordered
        // styles render white-on-white here because the tvOS root tints
        // controls with `.continuumOnSurface`.
        HStack(spacing: 24) {
            TVPrimaryPillButton(icon: "play.fill", title: primaryPlayLabel) {
                audioStore.play(
                    contentId: detail.contentId,
                    restart: false,
                    startPosition: resumePosition
                )
            }

            TVSecondaryPillButton(icon: "arrow.counterclockwise", title: "Start Over") {
                audioStore.play(contentId: detail.contentId, restart: true)
            }
        }
        #else
        HStack(spacing: 12) {
            Button {
                audioStore.play(
                    contentId: detail.contentId,
                    restart: false,
                    startPosition: resumePosition
                )
            } label: {
                Label(primaryPlayLabel, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                audioStore.play(contentId: detail.contentId, restart: true)
            } label: {
                Label("Start Over", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
        #endif
    }

    @ViewBuilder
    private func cover(size: CGFloat) -> some View {
        if let url = detail.posterUrl, !url.isEmpty {
            AsyncImageView(
                url: url,
                thumbhash: detail.posterThumbhash,
                targetSize: CGSize(width: size, height: size),
                contentMode: .fill
            )
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius)
                .fill(Color.continuumSurfaceElevated)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.system(size: size * 0.22, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func detailSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(sectionTitleFont)
                .fontWeight(.semibold)
                .foregroundColor(.continuumOnSurface)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func partRow(part: FileVersion, fallbackIndex: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(partTitle(part, fallbackIndex: fallbackIndex))
                    .font(rowTitleFont)
                    .lineLimit(1)
                Text(partSubtitle(part))
                    .font(rowMetaFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(PlayerTimeFormatter.formatRuntime(partDuration(part)))
                .font(rowMetaFont)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Row typography: tvOS uses the 10-foot scale instead of letting
    /// iOS semantic fonts balloon at TV sizes.
    private var rowTitleFont: Font {
        #if os(tvOS)
        return .continuumBody
        #else
        return .headline
        #endif
    }

    private var rowMetaFont: Font {
        #if os(tvOS)
        return .continuumCaption
        #else
        return .subheadline
        #endif
    }

    private func chapterRow(_ chapter: DisplayChapter) -> some View {
        Button {
            audioStore.play(
                contentId: detail.contentId,
                restart: false,
                startPosition: chapter.startSeconds
            )
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "list.bullet.indent")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                Text(chapter.title)
                    .font(rowTitleFont)
                    .lineLimit(1)
                Spacer()
                Text(PlayerTimeFormatter.formatHMS(chapter.startSeconds))
                    .font(rowMetaFont)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            #if os(tvOS)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            #endif
        }
        #if os(tvOS)
        .buttonStyle(TVAudiobookRowStyle())
        #else
        .buttonStyle(.plain)
        #endif
    }

    private func relatedRail(items: [AudiobookRelatedItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: railSpacing) {
                ForEach(items) { item in
                    Button {
                        onNavigateToItem(item.contentId)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            relatedPoster(item)
                            Text(item.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.continuumOnSurface)
                                .lineLimit(2, reservesSpace: true)
                            if let seriesIndex = item.seriesIndex {
                                Text("Book \(seriesIndex)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let year = item.year {
                                Text(String(year))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: relatedPosterWidth, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func relatedPoster(_ item: AudiobookRelatedItem) -> some View {
        if let url = item.posterUrl, !url.isEmpty {
            AsyncImageView(
                url: url,
                targetSize: CGSize(width: relatedPosterWidth, height: relatedPosterHeight),
                contentMode: .fill
            )
            .frame(width: relatedPosterWidth, height: relatedPosterHeight)
            .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius)
                .fill(Color.continuumSurfaceElevated)
                .frame(width: relatedPosterWidth, height: relatedPosterHeight)
                .overlay {
                    Image(systemName: "book.closed")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var parts: [FileVersion] {
        AudiobookPlaybackContext.audioParts(of: detail)
    }

    private var displayChapters: [DisplayChapter] {
        var offset = 0.0
        var chapters: [DisplayChapter] = []
        for (partPosition, part) in parts.enumerated() {
            for chapter in part.chapters ?? [] {
                let title: String
                if let chapterTitle = chapter.title, !chapterTitle.isEmpty {
                    title = chapterTitle
                } else {
                    title = "Chapter \(chapter.index + 1)"
                }
                chapters.append(DisplayChapter(
                    id: "\(part.fileId)-\(chapter.index)-\(chapter.startSeconds)",
                    title: title,
                    startSeconds: offset + chapter.startSeconds,
                    partTitle: partTitle(part, fallbackIndex: partPosition)
                ))
            }
            offset += partDuration(part)
        }
        return chapters.sorted { $0.startSeconds < $1.startSeconds }
    }

    private var otherNarrations: [AudiobookNarration] {
        detail.audiobook?.otherNarrations ?? []
    }

    private var metadataLine: String {
        var tokens: [String] = []
        if let authors = joinedNames(detail.audiobook?.authors), !authors.isEmpty {
            tokens.append(authors)
        }
        if let narrators = joinedNames(detail.audiobook?.narrators), !narrators.isEmpty {
            tokens.append("Narrated by \(narrators)")
        }
        let totalDuration = detail.audiobook?.totalDurationSeconds.map(Double.init)
            ?? detail.userData?.durationSeconds
            ?? parts.reduce(0) { $0 + partDuration($1) }
        let runtime = PlayerTimeFormatter.formatRuntime(totalDuration)
        if !runtime.isEmpty {
            tokens.append(runtime)
        }
        return tokens.joined(separator: "  ")
    }

    private var resumePosition: Double? {
        guard let position = detail.userData?.positionSeconds,
              position.isFinite,
              position > 30 else { return nil }
        if let duration = detail.userData?.durationSeconds,
           duration.isFinite,
           duration > 0,
           position >= duration - 5 {
            return nil
        }
        return position
    }

    private var primaryPlayLabel: String {
        if let resumePosition {
            return "Resume \(PlayerTimeFormatter.formatHMS(resumePosition))"
        }
        return "Play"
    }

    private func partTitle(_ part: FileVersion, fallbackIndex: Int) -> String {
        if let fileName = part.fileName, !fileName.isEmpty {
            return fileName
        }
        let rawIndex = part.presentationPartIndex ?? fallbackIndex
        let displayIndex = rawIndex <= 0 ? rawIndex + 1 : rawIndex
        return "Part \(displayIndex)"
    }

    private func partSubtitle(_ part: FileVersion) -> String {
        var tokens: [String] = []
        if let codec = part.codecAudio, !codec.isEmpty {
            tokens.append(codec.uppercased())
        }
        if let container = part.container, !container.isEmpty {
            tokens.append(container.uppercased())
        }
        if let bitrate = part.bitrate, bitrate > 0 {
            tokens.append("\(bitrate / 1000) kbps")
        }
        return tokens.isEmpty ? "Audio part" : tokens.joined(separator: "  ")
    }

    private func partDuration(_ part: FileVersion) -> Double {
        AudiobookPlaybackContext.partDuration(part)
    }

    private func joinedNames(_ people: [AudiobookPerson]?) -> String? {
        people?
            .map(\.name)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var coverSize: CGFloat {
        #if os(tvOS)
        return 360
        #else
        return 220
        #endif
    }

    private var relatedPosterWidth: CGFloat {
        #if os(tvOS)
        return 220
        #else
        return 110
        #endif
    }

    private var relatedPosterHeight: CGFloat {
        // Audiobook covers are square — don't stretch them into the
        // 2:3 poster shape the video rails use.
        relatedPosterWidth
    }

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        return 48
        #else
        return 30
        #endif
    }

    private var railSpacing: CGFloat {
        #if os(tvOS)
        return 30
        #else
        return 12
        #endif
    }

    private var topPadding: CGFloat {
        #if os(tvOS)
        return 0
        #else
        return 24
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(tvOS)
        return 80
        #else
        return 44
        #endif
    }

    private var titleFont: Font {
        #if os(tvOS)
        return .system(size: 56, weight: .bold)
        #else
        return .title2
        #endif
    }

    private var sectionTitleFont: Font {
        #if os(tvOS)
        return .title2
        #else
        return .headline
        #endif
    }

    private var headerAlignment: HorizontalAlignment {
        #if os(tvOS)
        return .leading
        #else
        return .center
        #endif
    }

    private var headerTextAlignment: TextAlignment {
        #if os(tvOS)
        return .leading
        #else
        return .center
        #endif
    }
}

private struct DisplayChapter: Identifiable, Hashable {
    let id: String
    let title: String
    let startSeconds: Double
    let partTitle: String
}

#if os(tvOS)
/// Native list-row focus grammar for chapter rows (mirrors
/// `TVLibraryPickerRowStyle`): white fill + black text on focus, faint
/// resting fill, gentle scale — instead of the plain-style halo that
/// blows a full-width row up into a giant white slab.
private struct TVAudiobookRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVAudiobookRowBody(configuration: configuration)
    }
}

private struct TVAudiobookRowBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundColor(isFocused ? .black : .white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.06))
            )
            .shadow(
                color: isFocused ? .black.opacity(0.4) : .clear,
                radius: isFocused ? 18 : 0,
                y: isFocused ? 8 : 0
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
#endif
