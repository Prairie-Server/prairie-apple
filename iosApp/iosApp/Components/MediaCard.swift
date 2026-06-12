import SwiftUI

/// Artwork shape for a `MediaCard`.
enum MediaCardAspect {
    /// 2:3 movie/series poster.
    case poster
    /// 1:1 tile for audiobook covers.
    case square
}

/// A poster-style media card with title, year, and optional progress.
/// On tvOS the card uses `.buttonStyle(.card)` which gives proper focus lift,
/// parallax, and title reveal — no manual focus effects required.
struct MediaCard: View {
    let title: String
    let posterUrl: String
    var thumbhash: String? = nil
    var year: Int? = nil
    var progress: Double? = nil
    var userState: MediaItemUserState? = nil
    /// Data for the optional overlay badges (resolution, ratings, …).
    /// `nil` skips overlay rendering on this card — callers that
    /// don't have an `OverlaySummary` available (e.g. people /
    /// collection thumbnails) leave this off.
    var overlayData: OverlayData? = nil
    let action: () -> Void
    /// tvOS-only: binding to the parent row's `@FocusState` so the parent
    /// can route default focus (`defaultFocus(_:_:priority: .userInitiated)`)
    /// to a specific card. Pass `nil` for callers that don't need row-level
    /// focus targeting.
    var focusedItemId: FocusState<String?>.Binding? = nil

    var contentId: String? = nil
    var onRemoveFromContinueWatching: (() -> Void)? = nil
    var onSetWatched: ((Bool) -> Void)? = nil
    var aspect: MediaCardAspect = .poster
    /// Overrides the theme's default card width. Skyline's dense landing
    /// rows (§5.6) pass 208 so two rows + the marquee fit above the fold;
    /// the poster keeps its 2:3 ratio.
    var cardWidthOverride: CGFloat? = nil

    @State private var playedOverride: Bool?
    @EnvironmentObject private var overlayStore: OverlayPrefsStore

    private var cardWidth: CGFloat { cardWidthOverride ?? ContinuumTheme.posterCardWidth }
    private var cardHeight: CGFloat {
        switch aspect {
        case .poster:
            cardWidth * (ContinuumTheme.posterCardHeight / ContinuumTheme.posterCardWidth)
        case .square:
            cardWidth
        }
    }

    var body: some View {
        #if os(tvOS)
        // tvOS: button label is just the poster (so .card style lifts the image),
        // then a title caption lives outside the button and reacts to focus via FocusState.
        FocusableMediaCard(
            title: title,
            year: year,
            cardWidth: cardWidth,
            action: action,
            focusedItemId: focusedItemId,
            itemId: contentId,
            isWatched: isPlayed,
            onRemoveFromContinueWatching: onRemoveFromContinueWatching,
            onSetWatched: onSetWatched.map { handler in
                { played in
                    playedOverride = played
                    handler(played)
                }
            }
        ) {
            posterImage
        }
        .onChange(of: userState?.played) { _, _ in
            playedOverride = nil
        }
        #else
        Group {
            if let contentId {
                NavigationLink(value: Route.itemDetail(contentId: contentId)) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: cardWidth)
        #endif
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            posterImage
            titleText
            yearText
        }
    }

    // MARK: - Subviews

    private var posterImage: some View {
        ZStack(alignment: .bottom) {
            AsyncImageView(
                url: posterUrl,
                thumbhash: thumbhash,
                targetSize: CGSize(width: cardWidth, height: cardHeight),
                contentMode: .fill
            )
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))

            // Server / user-customized overlays (resolution, HDR, ratings, …)
            // sit under the watched check + progress bar so those built-in
            // affordances always win the same corner if they conflict.
            if let overlayData, overlayStore.enabled {
                CardOverlays(data: overlayData, prefs: overlayStore.prefs, variant: .poster)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
            }

            // Progress bar at bottom of poster (inside rounded corners)
            if let progress, progress > 0 {
                VStack {
                    Spacer()
                    ProgressBar(value: progress)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
            }

            // Watched indicator — white circle with check (Plezy style)
            if isPlayed {
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.continuumOnSurface)
                            .frame(width: checkBadgeSize, height: checkBadgeSize)
                            .shadow(color: .black.opacity(0.3), radius: 4)
                        Image(systemName: "checkmark")
                            .font(.system(size: checkIconSize, weight: .bold))
                            .foregroundColor(Color.continuumBackground)
                    }
                }
                .padding(checkBadgePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private var isPlayed: Bool {
        playedOverride ?? (userState?.played == true)
    }

    private var titleText: some View {
        Text(title)
            .font(.continuumSubheadline)
            .foregroundColor(.continuumOnSurface)
            // Reserve 2 lines of space so single- and multi-line titles
            // produce the same overall card height — keeps posters in a
            // row top-aligned when titles wrap.
            .lineLimit(2, reservesSpace: true)
    }

    @ViewBuilder
    private var yearText: some View {
        if let year {
            Text(String(year))
                .font(.continuumCaption)
                .foregroundColor(.continuumSecondaryText)
        }
    }

    // MARK: - Metric helpers

    private var checkBadgeSize: CGFloat {
        #if os(tvOS)
        return 40
        #else
        return 20
        #endif
    }

    private var checkIconSize: CGFloat {
        #if os(tvOS)
        return 20
        #else
        return 10
        #endif
    }

    private var checkBadgePadding: CGFloat {
        #if os(tvOS)
        return 12
        #else
        return 6
        #endif
    }
}

// MARK: - tvOS Focusable wrapper

#if os(tvOS)
/// Wraps a poster inside a `.card` button so the image gets the native focus
/// lift/parallax, and renders a title + year below that bolds/brightens on focus.
private struct FocusableMediaCard<Content: View>: View {
    let title: String
    let year: Int?
    let cardWidth: CGFloat
    let action: () -> Void
    /// Parent row's focus tracking binding. When paired with `itemId`,
    /// the button binds via `.focused(_, equals: itemId)` so the row's
    /// `defaultFocus(... priority: .userInitiated)` can land focus here
    /// on d-pad entry.
    let focusedItemId: FocusState<String?>.Binding?
    let itemId: String?
    let isWatched: Bool
    let onRemoveFromContinueWatching: (() -> Void)?
    let onSetWatched: ((Bool) -> Void)?
    @ViewBuilder var content: () -> Content

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            mediaButton

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.continuumSubheadline)
                    .foregroundColor(isFocused ? .continuumOnSurface : .continuumOnSurface.opacity(0.85))
                    .lineLimit(2, reservesSpace: true)
                    .animation(.easeOut(duration: 0.15), value: isFocused)

                if let year {
                    Text(String(year))
                        .font(.continuumCaption)
                        .foregroundColor(.continuumSecondaryText)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .frame(width: cardWidth)
    }

    @ViewBuilder
    private var mediaButton: some View {
        let button = Button(action: action) {
            content()
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .applyRowFocus(focusedItemId, itemId: itemId)

        mediaButtonWithContext(button)
    }

    @ViewBuilder
    private func mediaButtonWithContext<ButtonContent: View>(_ button: ButtonContent) -> some View {
        if hasContextActions {
            button.contextMenu {
                contextActions
            }
        } else {
            button
        }
    }

    private var hasContextActions: Bool {
        onSetWatched != nil || onRemoveFromContinueWatching != nil
    }

    @ViewBuilder
    private var contextActions: some View {
        if let onSetWatched {
            Button {
                onSetWatched(!isWatched)
            } label: {
                Label(
                    isWatched ? "Mark as Unwatched" : "Mark as Watched",
                    systemImage: isWatched ? "circle" : "checkmark.circle"
                )
            }
        }

        if let onRemoveFromContinueWatching {
            Button(role: .destructive) {
                onRemoveFromContinueWatching()
            } label: {
                Label("Remove from Continue Watching", systemImage: "xmark.circle")
            }
        }
    }
}

private extension View {
    /// Conditionally binds this view to the parent row's `@FocusState`
    /// so `defaultFocus(... priority: .userInitiated)` upstream can land
    /// focus on it. No-op when either argument is nil (e.g., on iOS or
    /// when this card isn't inside a row that manages focus).
    @ViewBuilder
    func applyRowFocus(
        _ binding: FocusState<String?>.Binding?,
        itemId: String?
    ) -> some View {
        if let binding, let itemId {
            self.focused(binding, equals: itemId)
        } else {
            self
        }
    }
}
#endif
