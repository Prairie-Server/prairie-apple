#if os(tvOS)
import SwiftUI
import Nuke

// MARK: - Content payload

/// Display payload for the focus marquee (§5.4/§5.5), built from
/// section-item models only (§9): render whatever synopsis/badge/runtime
/// fields the payload already carries, omit what's missing, and never
/// block on a per-item detail fetch.
struct TVMarqueeContent: Equatable {
    /// Crossfade identity. Includes the source row so the same item
    /// focused from a different row still swaps (the eyebrow changes).
    let id: String
    /// The source row's title (`CONTINUE WATCHING`), preceded by the
    /// `marquee.tick` dash when rendered.
    let eyebrow: String
    let title: String
    /// Optional server logo art that may replace the text title once
    /// cached — the title always renders as text first.
    let logoUrl: String?
    /// Codec/HDR badge chips, display-formatted (`4K · DOLBY VISION · ATMOS`).
    let badges: [String]
    /// Dot-joined meta tokens after the badges: year · genre · runtime,
    /// or `S2 E7 · episode title · 23 min left` for episodic items.
    let metaParts: [String]
    let synopsis: String?
    let backdropUrl: String?
    let backdropThumbhash: String?
}

extension TVMarqueeContent {
    init(item: SectionItem, rowTitle: String) {
        let isEpisode = item.type.lowercased() == "episode"

        var meta: [String] = []
        if isEpisode {
            if let token = Self.episodeToken(season: item.seasonNumber, episode: item.episodeNumber) {
                meta.append(token)
            }
            meta.append(item.title)
            if let timeLeft = Self.timeLeftText(position: item.positionSeconds, duration: item.durationSeconds) {
                meta.append(timeLeft)
            } else if let runtime = Self.runtimeText(minutes: item.runtime) {
                meta.append(runtime)
            }
        } else {
            if let year = item.year, year > 0 { meta.append(String(year)) }
            if let genre = item.genres?.first(where: { !$0.isEmpty }) { meta.append(genre) }
            if let runtime = Self.runtimeText(minutes: item.runtime) { meta.append(runtime) }
            if let rating = item.ratingImdb { meta.append(String(format: "%.1f", rating)) }
        }

        self.init(
            id: "\(rowTitle)#\(item.contentId)",
            eyebrow: rowTitle,
            // Episodes headline with their series (`SEVERANCE`); the
            // episode itself moves to the meta line per §5.4.
            title: isEpisode ? (item.seriesTitle ?? item.title) : item.title,
            logoUrl: item.logoUrl,
            badges: Self.badges(from: item.overlaySummary),
            metaParts: meta,
            synopsis: item.overview,
            backdropUrl: Self.nonEmpty(item.backdropUrl) ?? item.posterUrl,
            backdropThumbhash: Self.nonEmpty(item.backdropUrl) != nil
                ? item.backdropThumbhash
                : item.posterThumbhash
        )
    }

    /// Collection preview (§6.2): name, count, poster-derived backdrop.
    init(collection: LibraryCollection, rowTitle: String) {
        var meta: [String] = []
        if let count = collection.itemCount, count > 0 {
            meta.append("\(count) \(count == 1 ? "item" : "items")")
        }
        if collection.kind == .userCollections {
            meta.append("User collection")
        }

        self.init(
            id: "\(rowTitle)#collection:\(collection.id)",
            eyebrow: rowTitle,
            title: collection.name,
            logoUrl: nil,
            badges: [],
            metaParts: meta,
            synopsis: nil,
            backdropUrl: collection.posterUrl,
            backdropThumbhash: collection.posterThumbhash
        )
    }

    // MARK: Formatting

    /// Badge chips from the section payload's `OverlaySummary` — the
    /// marquee shows the headline trio (resolution, dynamic range,
    /// audio), uppercased to the §4.1 badge style.
    private static func badges(from summary: OverlaySummary?) -> [String] {
        guard let summary else { return [] }
        var badges: [String] = []
        if let resolution = prettyResolution(summary.resolution) {
            badges.append(resolution)
        }
        if let hdr = nonEmpty(summary.hdr) {
            badges.append(hdr.localizedCaseInsensitiveContains("dv") || hdr.localizedCaseInsensitiveContains("dolby")
                ? "DOLBY VISION"
                : hdr.uppercased())
        }
        if let audio = nonEmpty(summary.audio) {
            badges.append(audio.localizedCaseInsensitiveContains("atmos") ? "ATMOS" : audio.uppercased())
        }
        return badges
    }

    private static func prettyResolution(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        switch value.lowercased() {
        case "2160p", "4k", "uhd": return "4K"
        case "4320p", "8k": return "8K"
        default: return value.uppercased()
        }
    }

    private static func episodeToken(season: Int?, episode: Int?) -> String? {
        switch (season, episode) {
        case let (season?, episode?): return "S\(season) E\(episode)"
        case let (season?, nil): return "Season \(season)"
        case let (nil, episode?): return "Episode \(episode)"
        default: return nil
        }
    }

    /// `23 min left` for items with a live resume point, mirroring the
    /// progress rules MediaRow uses for its bars.
    private static func timeLeftText(position: Double?, duration: Double?) -> String? {
        guard let position, let duration,
              duration > 0, position > 60, position / duration < 0.95 else {
            return nil
        }
        let remaining = max(Int(((duration - position) / 60).rounded(.up)), 1)
        return "\(remaining) min left"
    }

    private static func runtimeText(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return "\(minutes) min"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Debounce model

/// Focused-card → marquee state shared by the tvOS Home and library
/// Browse landings. Rows report card focus immediately; the marquee and
/// backdrop swap only after focus has rested 150 ms (§4.2), so scrubbing
/// across a row never flashes intermediate backdrops. While focus is in
/// chrome the last previewed item is retained — rows never report focus
/// loss, only focus gain.
@Observable
@MainActor
final class TVFocusMarqueeModel {
    /// The rested, currently-displayed content. `nil` until the first
    /// row reports focus — the marquee region stays scrim-only (§8).
    private(set) var content: TVMarqueeContent?
    /// Dominant-color wash behind the backdrop, sampled per displayed
    /// backdrop (same palette pipeline the hero carousel used).
    private(set) var tintColor: Color = .continuumBackground

    private var debounceTask: Task<Void, Never>?
    private var tintTask: Task<Void, Never>?
    private var lastSampledTintURL: String?

    /// Report card focus. Cancels any pending swap and schedules a new
    /// one at +150 ms; reporting the already-displayed content is a no-op.
    func preview(_ candidate: TVMarqueeContent) {
        debounceTask?.cancel()
        guard candidate != content else { return }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(ContinuumTheme.Skyline.marqueeRestDebounceMilliseconds))
            guard !Task.isCancelled else { return }
            self?.display(candidate)
        }
    }

    private func display(_ candidate: TVMarqueeContent) {
        content = candidate
        sampleTintIfNeeded(for: candidate.backdropUrl)
    }

    private func sampleTintIfNeeded(for urlString: String?) {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }
        guard urlString != lastSampledTintURL else { return }

        lastSampledTintURL = urlString
        tintTask?.cancel()
        tintTask = Task { [weak self] in
            let tint = await HeroBackdropPalette.tintColor(for: url)
            guard !Task.isCancelled, let self else { return }
            guard let tint else {
                if self.lastSampledTintURL == urlString {
                    self.lastSampledTintURL = nil
                }
                return
            }
            self.tintColor = tint
        }
    }
}

// MARK: - Marquee view

/// Passive billboard at the top of Home and the library Browse landings
/// (§5.4/§5.5): always previews the card the user is focused on, never
/// participates in focus, has no buttons. Crossfades 240 ms (snaps under
/// Reduce Motion) and is exposed to VoiceOver as a polite, non-interrupting
/// description of the focused item.
struct TVFocusMarquee: View {
    enum Scale {
        /// Home — full-bleed scale (block top 218, title 84, eyebrow 17).
        case home
        /// Library landing — compact spotlight scale (top 246, title 66,
        /// eyebrow 16) so row 1 stays fully visible above the fold.
        case library

        var contentTop: CGFloat {
            switch self {
            case .home: ContinuumTheme.Skyline.marqueeTopHome
            case .library: ContinuumTheme.Skyline.marqueeTopLibrary
            }
        }

        var eyebrowSize: CGFloat {
            switch self {
            case .home: ContinuumTheme.Skyline.marqueeEyebrowSizeHome
            case .library: ContinuumTheme.Skyline.marqueeEyebrowSizeLibrary
            }
        }

        var titleSize: CGFloat {
            switch self {
            case .home: ContinuumTheme.Skyline.marqueeTitleSizeHome
            case .library: ContinuumTheme.Skyline.marqueeTitleSizeLibrary
            }
        }

        var metaSize: CGFloat {
            switch self {
            case .home: ContinuumTheme.Skyline.marqueeMetaSizeHome
            case .library: ContinuumTheme.Skyline.marqueeMetaSizeLibrary
            }
        }
    }

    let content: TVMarqueeContent?
    let scale: Scale

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let content {
                TVMarqueeBlock(content: content, scale: scale)
                    .id(content.id)
                    .transition(.opacity)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding(.leading, ContinuumTheme.Skyline.safeAreaX)
        .padding(.top, scale.contentTop)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .allowsHitTesting(false)
        .focusEffectDisabled()
        // The model swaps `content` outside any animation transaction, so
        // the crossfade is driven here, keyed on the item id (§4.2 240 ms).
        // Reduce Motion drops the animation entirely → the swap snaps.
        .animation(
            reduceMotion ? nil : .easeInOut(duration: ContinuumTheme.Skyline.marqueeCrossfadeDuration),
            value: content?.id
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.updatesFrequently)
        .onChange(of: content) { _, newValue in
            guard let newValue else { return }
            announce(newValue)
        }
    }

    private var accessibilityDescription: String {
        guard let content else { return "" }
        return ([content.eyebrow, content.title] + content.metaParts + [content.synopsis ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Polite live region: queue a low-priority announcement that never
    /// interrupts in-progress speech while the user scrubs a row.
    private func announce(_ content: TVMarqueeContent) {
        var message = AttributedString(accessibilityDescription)
        message.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(message).post()
    }
}

// MARK: - Content block

/// One marquee "frame": eyebrow, title (text first, cached logo art may
/// swap in), badge + meta line, synopsis. Identity is keyed on the
/// content id by the parent so a content change crossfades whole blocks.
private struct TVMarqueeBlock: View {
    let content: TVMarqueeContent
    let scale: TVFocusMarquee.Scale

    /// Server logo art, swapped in only once decoded — the text title
    /// renders immediately and the crossfade never waits on this fetch.
    @State private var logoImage: UIImage?
    @State private var logoTask: Task<Void, Never>?
    /// When the text title wraps to two lines the synopsis drops to one
    /// (§5.4) so the block never collides with row 1.
    @State private var titleWrapsTwoLines = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            eyebrow

            titleSlot

            metaLine

            if let synopsis = content.synopsis, !synopsis.isEmpty {
                Text(synopsis)
                    .font(.system(size: ContinuumTheme.Skyline.marqueeSynopsisSize, weight: .regular))
                    .lineSpacing(6)
                    .foregroundStyle(Color.continuumSecondaryText)
                    .lineLimit(titleWrapsTwoLines ? 1 : 2)
                    .frame(maxWidth: ContinuumTheme.Skyline.marqueeSynopsisMaxWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: ContinuumTheme.Skyline.marqueeContentWidth, alignment: .leading)
        .onAppear { loadLogoIfCached() }
        .onDisappear {
            logoTask?.cancel()
            logoTask = nil
        }
    }

    private var eyebrow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: ContinuumTheme.Skyline.marqueeTickCornerRadius)
                .fill(Color.continuumMarqueeTick)
                .frame(
                    width: ContinuumTheme.Skyline.marqueeTickSize.width,
                    height: ContinuumTheme.Skyline.marqueeTickSize.height
                )

            Text(content.eyebrow.uppercased())
                .font(.system(size: scale.eyebrowSize, weight: .bold))
                .tracking(scale.eyebrowSize * 0.30)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var titleSlot: some View {
        if let logoImage {
            Image(uiImage: logoImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    maxWidth: ContinuumTheme.Skyline.marqueeLogoMaxSize.width,
                    maxHeight: ContinuumTheme.Skyline.marqueeLogoMaxSize.height,
                    alignment: .leading
                )
                .transition(reduceMotion ? .identity : .opacity.animation(.easeInOut(duration: 0.2)))
                .accessibilityHidden(true)
        } else {
            Text(content.title)
                .font(.system(size: scale.titleSize, weight: .heavy).leading(.tight))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    titleWrapsTwoLines = height > scale.titleSize * 1.4
                }
        }
    }

    @ViewBuilder
    private var metaLine: some View {
        if !content.badges.isEmpty || !content.metaParts.isEmpty {
            HStack(spacing: 10) {
                ForEach(content.badges, id: \.self) { badge in
                    badgeChip(badge)
                }

                if !content.metaParts.isEmpty {
                    Text(content.metaParts.joined(separator: " · "))
                        .font(.system(size: scale.metaSize, weight: .medium))
                        .foregroundStyle(Color.continuumSecondaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    private func badgeChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: ContinuumTheme.Skyline.marqueeBadgeSize, weight: .semibold))
            .tracking(ContinuumTheme.Skyline.marqueeBadgeSize * 0.08)
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.continuumChromeRestingFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
            }
    }

    // MARK: Logo swap-in

    /// Show cached logo art instantly; otherwise fetch at low priority
    /// and swap in whenever it lands. The text title is never delayed.
    private func loadLogoIfCached() {
        guard let logoUrl = content.logoUrl, !logoUrl.isEmpty,
              let url = URL(string: logoUrl) else {
            return
        }

        let request = ImageRequest(url: url, priority: .low)
        if let cached = ImagePipeline.shared.cache[request] {
            logoImage = cached.image
            return
        }

        logoTask = Task { @MainActor in
            guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
            guard !Task.isCancelled else { return }
            logoImage = image
        }
    }
}
#endif
