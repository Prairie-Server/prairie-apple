import SwiftUI

struct AudiobookDetailContent: View {
    let detail: ItemDetail
    let onNavigateToItem: (String) -> Void

    @Environment(AudioPlaybackStore.self) private var audioStore

    #if !os(tvOS)
    @State private var showAllChapters = false
    #endif

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        phoneBody
        #endif
    }

    @ViewBuilder
    private var aboutSection: some View {
        if let overview = detail.overview, !overview.isEmpty {
            detailSection(title: "About") {
                Text(overview)
                    .font(aboutFont)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }

    /// Series / narration / recommendation rails — identical on every
    /// platform, so both layouts share them.
    @ViewBuilder
    private var commonSections: some View {
        if let series = detail.audiobook?.series, !series.entries.isEmpty {
            detailSection(title: series.name ?? "Series") {
                relatedRail(items: series.entries)
            }
        }

        if !otherNarrations.isEmpty {
            narrationsSection
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

    #if os(tvOS)
    private var tvBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                header
                aboutSection

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

                commonSections
            }
            .padding(.horizontal, ContinuumTheme.safePadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
        .continuumBackground()
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            audiobookBackdrop
            HStack(alignment: .center, spacing: 56) {
                cover(size: coverSize)
                headerText
                    .frame(maxWidth: 900, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ContinuumTheme.safePadding)
            .padding(.bottom, 64)
            .padding(.top, 120)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    private var narrationsSection: some View {
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

    // MARK: - tvOS header (10-foot cinematic layout)

    #if os(tvOS)
    private var headerText: some View {
        VStack(alignment: headerAlignment, spacing: 14) {
            audiobookEyebrow
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

            if !otherNarrations.isEmpty {
                Menu {
                    ForEach(otherNarrations) { narration in
                        Button { onNavigateToItem(narration.contentId) } label: {
                            Text(narration.narrators.isEmpty ? narration.title
                                 : narration.narrators.joined(separator: ", "))
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.wave.2").font(.system(size: 22, weight: .semibold))
                        Text("NARRATION").font(.system(size: 18, weight: .bold)).tracking(1.0).opacity(0.6)
                        Text(currentNarratorLabel).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).opacity(0.6)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(TVPillButtonStyle(kind: .secondary))
            }
        }
    }

    /// A blurred, darkened wash of the square cover stands in for a 16:9
    /// backdrop, keeping the audiobook page in the cinematic family.
    @ViewBuilder
    private var audiobookBackdrop: some View {
        ZStack {
            if let url = detail.posterUrl, !url.isEmpty {
                AsyncImageView(url: url, thumbhash: detail.posterThumbhash,
                               targetSize: CGSize(width: 600, height: 600), contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 760)
                    .clipped()
                    .blur(radius: 60)
                    .opacity(0.5)
            } else {
                Color.continuumSurface.frame(height: 760)
            }
            LinearGradient(
                stops: [
                    .init(color: Color.continuumBackground.opacity(0.55), location: 0.0),
                    .init(color: Color.continuumBackground.opacity(0.30), location: 0.5),
                    .init(color: Color.continuumBackground, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 760)
        }
        .frame(height: 760)
        .clipped()
    }

    private var audiobookEyebrow: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.85))
                .frame(width: 34, height: 4).cornerRadius(2)
            Text("AUDIOBOOK")
                .font(.system(size: 18, weight: .bold)).tracking(3)
                .foregroundColor(.white.opacity(0.78))
        }
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
                    .font(.continuumBody)
                    .lineLimit(1)
                Spacer()
                Text(PlayerTimeFormatter.formatHMS(chapter.startSeconds))
                    .font(.continuumCaption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(TVAudiobookRowStyle())
    }

    private func partRow(part: FileVersion, fallbackIndex: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(partTitle(part, fallbackIndex: fallbackIndex))
                    .font(.continuumBody)
                    .lineLimit(1)
                Text(partSubtitle(part))
                    .font(.continuumCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(PlayerTimeFormatter.formatRuntime(partDuration(part)))
                .font(.continuumCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    #endif

    // MARK: - iOS / macOS hero

    #if !os(tvOS)
    private var phoneBody: some View {
        // The GeometryReader captures the real top safe-area inset *before*
        // the ScrollView ignores it, so the hero column can clear the status
        // bar while the backdrop still bleeds to the physical top edge.
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    phoneHero(topInset: topInset)
                    phoneSections
                        .padding(.horizontal, ContinuumTheme.safePadding)
                        .padding(.top, sectionSpacing)
                        .padding(.bottom, bottomPadding)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .continuumBackground()
    }

    private var phoneSections: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            aboutSection

            if !displayChapters.isEmpty {
                phoneChaptersSection
            }

            if parts.count > 1 {
                phonePartsSection
            }

            commonSections
            phoneDetailsLine
        }
    }

    /// Identity-first hero in the house style: the square cover floats on a
    /// blurred, color-extracted wash of itself (the §5.5 detail backdrop the
    /// movie hero already uses, adapted for square art), with a clear
    /// Title → Author → Narrator hierarchy and a progress-forward CTA. The
    /// backdrop is a top-pinned background so it fills up under the status
    /// bar; the cover is inset past the safe area so it clears it.
    private func phoneHero(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            phoneCover
                .padding(.top, topInset + 14)
            phoneIdentity
                .padding(.top, 20)
            phoneProgressActions
                .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ContinuumTheme.safePadding)
        .background(alignment: .top) {
            phoneBackdrop
        }
    }

    private var phoneBackdrop: some View {
        ZStack {
            if let url = detail.posterUrl, !url.isEmpty {
                AsyncImageView(
                    url: url,
                    thumbhash: detail.posterThumbhash,
                    targetSize: CGSize(width: 420, height: 420),
                    contentMode: .fill
                )
                .frame(height: phoneBackdropHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .blur(radius: 48, opaque: true)
                .opacity(0.55)
            } else {
                Color.continuumSurface.frame(height: phoneBackdropHeight)
            }
            LinearGradient(
                stops: [
                    .init(color: Color.continuumBackground.opacity(0.30), location: 0.0),
                    .init(color: Color.continuumBackground.opacity(0.72), location: 0.55),
                    .init(color: Color.continuumBackground, location: 0.95),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: phoneBackdropHeight)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var phoneCover: some View {
        Group {
            if let url = detail.posterUrl, !url.isEmpty {
                AsyncImageView(
                    url: url,
                    thumbhash: detail.posterThumbhash,
                    targetSize: CGSize(width: phoneCoverSize, height: phoneCoverSize),
                    contentMode: .fill
                )
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.continuumSurfaceElevated)
                    .overlay {
                        Image(systemName: "headphones")
                            .font(.system(size: phoneCoverSize * 0.2, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: phoneCoverSize, height: phoneCoverSize)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 26, x: 0, y: 16)
    }

    private var phoneIdentity: some View {
        VStack(spacing: 0) {
            Text("AUDIOBOOK")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(.continuumOnSurface)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.continuumSurfaceElevated))

            Text(displayTitle)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .foregroundColor(.continuumOnSurface)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            if let seriesLineText {
                Text(seriesLineText.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 7)
            }

            if let authorSummary {
                Text(authorSummary)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.continuumOnSurface)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }

            if let narratorSummary {
                Text("Narrated by \(narratorSummary)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 4)
            }

            if !metaTokens.isEmpty {
                Text(metaTokens.joined(separator: "  ·  "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 11)
            }
        }
        .frame(maxWidth: 560)
    }

    private var phoneProgressActions: some View {
        VStack(spacing: 14) {
            if resumeFraction != nil {
                HStack {
                    Text("\(percentComplete)% complete")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.continuumOnSurface)
                    Spacer()
                    Text("\(PlayerTimeFormatter.formatRuntime(timeLeftSeconds)) left")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            AudiobookResumePill(
                icon: primaryActionIcon,
                title: primaryActionLabel,
                progress: resumeFraction
            ) {
                primaryAction()
            }

            phoneSecondaryControls
        }
        .frame(maxWidth: 420)
    }

    private var phoneSecondaryControls: some View {
        HStack(alignment: .top, spacing: 26) {
            phoneControl("Start Over") {
                PhoneCircleActionButton(
                    icon: "arrow.counterclockwise",
                    accessibilityLabel: "Start Over"
                ) {
                    audioStore.play(contentId: detail.contentId, restart: true)
                }
            }

            phoneControl("Speed") {
                phoneSpeedControl
            }

            if !otherNarrations.isEmpty {
                phoneControl("Narration") {
                    PhoneCircleMenuButton(icon: "person.wave.2", accessibilityLabel: "Narration") {
                        ForEach(otherNarrations) { narration in
                            Button {
                                onNavigateToItem(narration.contentId)
                            } label: {
                                Text(narration.narrators.isEmpty
                                     ? narration.title
                                     : narration.narrators.joined(separator: ", "))
                            }
                        }
                    }
                }
            }
        }
    }

    private var phoneSpeedControl: some View {
        Menu {
            ForEach(speedOptions, id: \.self) { rate in
                Button {
                    audioStore.player.setPlaybackRate(rate)
                } label: {
                    if abs(audioStore.player.playbackRate - rate) < 0.01 {
                        Label(speedLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(rate))
                    }
                }
            }
        } label: {
            Text(speedLabel(audioStore.player.playbackRate))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                )
        }
        .accessibilityLabel("Playback Speed")
    }

    @ViewBuilder
    private func phoneControl<Content: View>(
        _ caption: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(spacing: 7) {
            content()
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var phoneChaptersSection: some View {
        detailSection(title: "Chapters") {
            VStack(spacing: 0) {
                ForEach(Array(visibleChapters.enumerated()), id: \.element.id) { index, chapter in
                    phoneChapterRow(chapter, showsDivider: index > 0)
                }

                if displayChapters.count > chapterCollapseLimit {
                    Button {
                        withAnimation(.easeInOut(duration: ContinuumTheme.normalDuration)) {
                            showAllChapters.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showAllChapters
                                 ? "Show less"
                                 : "Show all \(displayChapters.count) chapters")
                            Image(systemName: showAllChapters ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func phoneChapterRow(_ chapter: DisplayChapter, showsDivider: Bool) -> some View {
        Button {
            audioStore.play(
                contentId: detail.contentId,
                restart: false,
                startPosition: chapter.startSeconds
            )
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.continuumOnSurface)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.07))
                            .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                    )
                Text(chapter.title)
                    .font(.system(size: 15))
                    .foregroundColor(.continuumOnSurface)
                    .lineLimit(1)
                Spacer()
                Text(PlayerTimeFormatter.formatHMS(chapter.startSeconds))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if showsDivider {
                    Rectangle()
                        .fill(Color.continuumDivider)
                        .frame(height: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var phonePartsSection: some View {
        detailSection(title: "Parts") {
            VStack(spacing: 0) {
                ForEach(parts.indices, id: \.self) { index in
                    phonePartRow(parts[index], index: index, showsDivider: index > 0)
                }
            }
        }
    }

    private func phonePartRow(_ part: FileVersion, index: Int, showsDivider: Bool) -> some View {
        Button {
            audioStore.play(
                contentId: detail.contentId,
                restart: false,
                startPosition: partStartOffset(index)
            )
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.continuumOnSurface)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.07))
                            .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                    )
                Text(partTitle(part, fallbackIndex: index))
                    .font(.system(size: 15))
                    .foregroundColor(.continuumOnSurface)
                    .lineLimit(1)
                Spacer()
                Text(PlayerTimeFormatter.formatRuntime(partDuration(part)))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if showsDivider {
                    Rectangle()
                        .fill(Color.continuumDivider)
                        .frame(height: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var phoneDetailsLine: some View {
        if !formatTokens.isEmpty {
            Text(formatTokens.joined(separator: "  ·  "))
                .font(.system(size: 12))
                .foregroundColor(.continuumOnSurface.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #endif

    // MARK: - Shared section scaffolding

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

    // MARK: - Audiobook timeline data

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

    private func partTitle(_ part: FileVersion, fallbackIndex: Int) -> String {
        if let fileName = part.fileName, !fileName.isEmpty {
            return fileName
        }
        let rawIndex = part.presentationPartIndex ?? fallbackIndex
        let displayIndex = rawIndex <= 0 ? rawIndex + 1 : rawIndex
        return "Part \(displayIndex)"
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

    #if os(tvOS)
    private var currentNarratorLabel: String {
        guard let names = joinedNames(detail.audiobook?.narrators), !names.isEmpty else {
            return "Default"
        }
        return names
    }

    private var metadataLine: String {
        var tokens: [String] = []
        if let authors = joinedNames(detail.audiobook?.authors), !authors.isEmpty {
            tokens.append(authors)
        }
        if let narrators = joinedNames(detail.audiobook?.narrators), !narrators.isEmpty {
            tokens.append("Narrated by \(narrators)")
        }
        let runtime = PlayerTimeFormatter.formatRuntime(totalDurationSeconds)
        if !runtime.isEmpty {
            tokens.append(runtime)
        }
        return tokens.joined(separator: "  ")
    }

    private var primaryPlayLabel: String {
        if let resumePosition {
            return "Resume \(PlayerTimeFormatter.formatHMS(resumePosition))"
        }
        return "Play"
    }
    #endif

    /// Total book duration, preferring the server's authoritative value and
    /// falling back to the stitched part durations.
    private var totalDurationSeconds: Double {
        if let total = detail.audiobook?.totalDurationSeconds, total > 0 {
            return Double(total)
        }
        if let duration = detail.userData?.durationSeconds, duration > 0 {
            return duration
        }
        return parts.reduce(0) { $0 + partDuration($1) }
    }

    /// Codec / container metadata is server-tooling detail — kept off the
    /// hero entirely and shown without bitrate (the old "0 kbps" came from
    /// integer-dividing a kbps value by 1000).
    private func partSubtitle(_ part: FileVersion) -> String {
        var tokens: [String] = []
        if let codec = part.codecAudio, !codec.isEmpty {
            tokens.append(codec.uppercased())
        }
        if let container = part.container, !container.isEmpty {
            tokens.append(container.uppercased())
        }
        return tokens.isEmpty ? "Audio part" : tokens.joined(separator: "  ")
    }

    // MARK: - iOS / macOS hero data

    #if !os(tvOS)
    private var displayTitle: String {
        AudiobookDetailFormatting.cleanTitle(detail.title, seriesName: detail.audiobook?.series?.name)
    }

    /// The series total comes from the title's "(N of M)" locator rather
    /// than the series grouping's entry count — the grouping can include
    /// alternate editions/narrations, which inflates the count (e.g. "of 19"
    /// for a 5-book series).
    private var seriesLineText: String? {
        let volume = AudiobookDetailFormatting.volume(in: detail.title)
        return AudiobookDetailFormatting.seriesLine(
            name: detail.audiobook?.series?.name,
            index: currentSeriesIndex ?? volume.index,
            total: volume.total
        )
    }

    private var currentSeriesIndex: Int? {
        detail.audiobook?.series?.entries
            .first(where: { $0.contentId == detail.contentId })?
            .seriesIndex
    }

    private var authorSummary: String? {
        AudiobookDetailFormatting.peopleSummary(
            detail.audiobook?.authors.map(\.name) ?? [],
            visible: 3
        )
    }

    private var narratorSummary: String? {
        AudiobookDetailFormatting.peopleSummary(
            detail.audiobook?.narrators.map(\.name) ?? [],
            visible: 2
        )
    }

    /// Compact, content-y metadata for the hero (interpunct-joined): runtime,
    /// publisher, year. Codec/bitrate intentionally excluded.
    private var metaTokens: [String] {
        var tokens: [String] = []
        let runtime = PlayerTimeFormatter.formatRuntime(totalDurationSeconds)
        if !runtime.isEmpty { tokens.append(runtime) }
        if let publisher = detail.audiobook?.publisher, !publisher.isEmpty {
            tokens.append(publisher)
        }
        if let year = detail.year { tokens.append(String(year)) }
        return tokens
    }

    /// Quiet, deemphasised technical line at the foot of the page.
    private var formatTokens: [String] {
        guard let primary = parts.first else { return [] }
        var tokens: [String] = []
        if let codec = primary.codecAudio, !codec.isEmpty {
            tokens.append(codec.uppercased())
        }
        if let container = primary.container, !container.isEmpty {
            tokens.append(container.uppercased())
        }
        if parts.count > 1 {
            tokens.append("\(parts.count) parts")
        }
        let runtime = PlayerTimeFormatter.formatRuntime(totalDurationSeconds)
        if !runtime.isEmpty { tokens.append(runtime) }
        return tokens
    }

    private var positionSeconds: Double {
        max(0, detail.userData?.positionSeconds ?? 0)
    }

    /// Listening progress 0...1, only when there's a meaningful resume point.
    private var resumeFraction: Double? {
        guard resumePosition != nil, totalDurationSeconds > 0 else { return nil }
        return min(1, max(0, positionSeconds / totalDurationSeconds))
    }

    private var percentComplete: Int {
        Int((resumeFraction ?? 0) * 100 + 0.5)
    }

    private var timeLeftSeconds: Double {
        max(0, totalDurationSeconds - positionSeconds)
    }

    private var isFinished: Bool {
        if detail.userData?.played == true { return true }
        guard totalDurationSeconds > 0, positionSeconds > 0 else { return false }
        return positionSeconds >= totalDurationSeconds - 5
    }

    private var primaryActionLabel: String {
        if resumePosition != nil { return "Resume" }
        if isFinished { return "Play Again" }
        return "Play"
    }

    private var primaryActionIcon: String {
        resumePosition == nil && isFinished ? "arrow.counterclockwise" : "play.fill"
    }

    private func primaryAction() {
        if let resumePosition {
            audioStore.play(contentId: detail.contentId, restart: false, startPosition: resumePosition)
        } else if isFinished {
            audioStore.play(contentId: detail.contentId, restart: true)
        } else {
            audioStore.play(contentId: detail.contentId, restart: false)
        }
    }

    private func partStartOffset(_ index: Int) -> Double {
        var offset = 0.0
        for position in 0..<index where parts.indices.contains(position) {
            offset += partDuration(parts[position])
        }
        return offset
    }

    private var visibleChapters: [DisplayChapter] {
        showAllChapters ? displayChapters : Array(displayChapters.prefix(chapterCollapseLimit))
    }

    private let chapterCollapseLimit = 8

    private let speedOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private func speedLabel(_ rate: Double) -> String {
        let value = rate.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rate))
            : String(format: "%g", rate)
        return "\(value)×"
    }
    #endif

    // MARK: - Platform metrics

    private var sectionTitleFont: Font {
        #if os(tvOS)
        return .title2
        #else
        return .headline
        #endif
    }

    private var aboutFont: Font {
        #if os(tvOS)
        return .body
        #else
        return .system(size: 15)
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
        return 0
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(tvOS)
        return 80
        #else
        return 44
        #endif
    }

    #if os(tvOS)
    private var coverSize: CGFloat { 360 }

    private var titleFont: Font { .system(size: 56, weight: .bold) }

    private var headerAlignment: HorizontalAlignment { .leading }

    private var headerTextAlignment: TextAlignment { .leading }
    #else
    private var phoneCoverSize: CGFloat { 196 }

    private var phoneBackdropHeight: CGFloat { 470 }
    #endif
}

private struct DisplayChapter: Identifiable, Hashable {
    let id: String
    let title: String
    let startSeconds: Double
    let partTitle: String
}

#if !os(tvOS)
/// Solid-white capsule resume/play button with the in-pill progress bar
/// the design language specifies for in-progress items (§5.5): a thin black
/// track + fill hugging the bottom of the pill.
private struct AudiobookResumePill: View {
    let icon: String
    let title: String
    let progress: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                ZStack {
                    Capsule().fill(Color.white)
                    if let progress, progress > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.black.opacity(0.16))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(Color.black.opacity(0.82))
                                    .frame(width: max(6, geo.size.width * progress), height: 5)
                            }
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
#endif

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
                RoundedRectangle(cornerRadius: ContinuumTheme.smallCornerRadius, style: .continuous)
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
