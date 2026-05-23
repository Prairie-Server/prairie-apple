#if os(tvOS)
import SwiftUI

/// tvOS-only poster card. Uses the cached Nuke renderer so scrolling through
/// a large grid doesn't re-download posters as cells are reused.
///
/// `.buttonStyle(.card)` gives us native focus lift + parallax + shadow, so
/// we do not roll our own scale animation. A title caption lives below the
/// card and brightens on focus.
struct TVMediaCard: View {
    let title: String
    let posterUrl: String
    var year: Int? = nil
    var userState: MediaItemUserState? = nil
    /// Data for optional overlay badges. `nil` skips overlay rendering;
    /// callers without per-item OverlaySummary should leave it off.
    var overlayData: OverlayData? = nil
    let action: () -> Void
    /// Width of the poster. Defaults to the theme's standard poster size.
    /// Override with a smaller value in space-constrained grids (e.g. the
    /// Library tab where the alphabet rail forces cards to shrink).
    var cardWidth: CGFloat = ContinuumTheme.posterCardWidth
    var prefersDefaultFocus: Bool = false
    var defaultFocusNamespace: Namespace.ID? = nil

    @FocusState private var isFocused: Bool
    @EnvironmentObject private var overlayStore: OverlayPrefsStore

    // Standard 2:3 movie-poster aspect ratio — height tracks width.
    private var cardHeight: CGFloat { cardWidth * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: action) {
                posterImage
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .applyDefaultFocusIfNeeded(
                prefersDefaultFocus,
                namespace: defaultFocusNamespace
            )

            caption
        }
        .frame(width: cardWidth)
    }

    // MARK: - Subviews

    private var posterImage: some View {
        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(
                url: posterUrl,
                targetSize: CGSize(width: cardWidth, height: cardHeight),
                contentMode: .fill
            )
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))

            if let overlayData, overlayStore.enabled {
                CardOverlays(data: overlayData, prefs: overlayStore.prefs, variant: .poster)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
            }

            if userState?.played == true {
                watchedBadge
                    .padding(12)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    // Plex-style: centered title with year directly underneath in a
    // lighter weight + dimmer color. Single-line truncation keeps the
    // caption a uniform two-row block across the whole grid.
    private var caption: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isFocused ? .continuumOnSurface : .continuumOnSurface.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)

            if let year {
                Text(String(year))
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.continuumSecondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: cardWidth, alignment: .center)
    }

    private var watchedBadge: some View {
        ZStack {
            Circle()
                .fill(Color.continuumOnSurface)
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.3), radius: 4)
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color.continuumBackground)
        }
    }
}

private extension View {
    @ViewBuilder
    func applyDefaultFocusIfNeeded(_ prefersDefaultFocus: Bool, namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.prefersDefaultFocus(prefersDefaultFocus, in: namespace)
        } else {
            self
        }
    }
}
#endif
