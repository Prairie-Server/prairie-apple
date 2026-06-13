#if os(tvOS)
import SwiftUI

/// Collection fan card (Skyline §5.6): a 430×234 landscape tile with a
/// left cluster of three fanned mini posters and a right block carrying
/// the collection name + item count. Used on the Browse `Collections` row
/// (§6.2) and the `Collections` pill grid (§6.3).
///
/// Focus grammar matches `TVMediaCard` (scale 1.05 + drop shadow), with an
/// added 2 px white border per the §5.6 surface spec. No outline ring.
///
/// Artwork: the collection model exposes only a single `posterUrl`
/// (`LibraryCollection.posterUrl`) — it carries no member-item posters — so
/// the three minis are derived from that one poster. When the poster is
/// missing the card fans generated gradient tiles instead, gracefully
/// degrading rather than blocking on a per-collection detail fetch. If the
/// server later returns member posters, swap `fanPosters` to read them.
struct TVCollectionFanCard: View {
    let collection: LibraryCollection
    let action: () -> Void

    /// Default-focus hook for the grid's first card on tab entry.
    var prefersDefaultFocus: Bool = false
    var defaultFocusNamespace: Namespace.ID? = nil
    /// External focus binding so a parent row can route d-pad-entry focus
    /// onto a specific card (mirrors `TVMediaCard.focusBinding`).
    var focusBinding: FocusState<String?>.Binding? = nil
    var focusContentId: String? = nil

    @FocusState private var isFocused: Bool

    private var width: CGFloat { ContinuumTheme.Skyline.fanCardWidth }
    private var height: CGFloat { ContinuumTheme.Skyline.fanCardHeight }
    private var radius: CGFloat { ContinuumTheme.Skyline.fanCardCornerRadius }

    var body: some View {
        Button(action: action) {
            surface
        }
        .buttonStyle(TVFanCardButtonStyle(cornerRadius: radius))
        .focused($isFocused)
        .applyDefaultFocusIfNeeded(prefersDefaultFocus, namespace: defaultFocusNamespace)
        .applyFanFocusBinding(focusBinding, contentId: focusContentId)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Surface

    private var surface: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: radius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.continuumFanCardSurfaceTop,
                            Color.continuumFanCardSurfaceBottom,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(ContinuumTheme.Skyline.fanCardSurfaceOpacity)

            HStack(spacing: 0) {
                fanCluster
                    .frame(width: width * 0.46)

                rightBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 22)
            }
            .padding(.vertical, 16)
            .padding(.leading, 18)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay {
            // Resting hairline; thickens to the 2 px white focus border.
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(
                    isFocused ? Color.white : Color.continuumOutline,
                    lineWidth: isFocused ? ContinuumTheme.Skyline.fanCardFocusBorderWidth : 1
                )
        }
    }

    // MARK: - Fan cluster

    /// Three mini posters fanned back→front at the §5.6 rotations, offset
    /// horizontally so they read as a deck. Degrades to whatever art is
    /// available (see `fanPosters`).
    private var fanCluster: some View {
        let posters = fanPosters
        let step = ContinuumTheme.Skyline.fanMiniPosterHorizontalStep
        let rotations = ContinuumTheme.Skyline.fanMiniPosterRotations

        return ZStack {
            ForEach(Array(posters.enumerated()), id: \.offset) { index, poster in
                miniPoster(poster)
                    .rotationEffect(.degrees(rotations[index]))
                    // Center the deck: index 0 (back) sits left, the front
                    // poster leans right.
                    .offset(x: CGFloat(index) * step - step)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func miniPoster(_ poster: FanPoster) -> some View {
        let w = ContinuumTheme.Skyline.fanMiniPosterWidth
        let h = ContinuumTheme.Skyline.fanMiniPosterHeight
        let shape = RoundedRectangle(cornerRadius: ContinuumTheme.Skyline.fanMiniPosterCornerRadius)

        Group {
            switch poster {
            case .artwork(let url, let thumbhash):
                CachedAsyncImage(
                    url: url,
                    targetSize: CGSize(width: w, height: h),
                    thumbhash: thumbhash,
                    contentMode: .fill
                )
            case .placeholder:
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.50, brightness: 0.42),
                            Color(hue: hue, saturation: 0.32, brightness: 0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .frame(width: w, height: h)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
    }

    // MARK: - Right block

    private var rightBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(collection.name)
                .font(.system(size: ContinuumTheme.Skyline.fanCardNameSize, weight: .bold))
                .foregroundColor(.continuumOnSurface)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)

            if let countText {
                Text(countText)
                    .font(.system(size: ContinuumTheme.Skyline.fanCardCountSize, weight: .semibold))
                    .tracking(ContinuumTheme.Skyline.fanCardCountTracking)
                    .foregroundColor(.continuumOnSurface.opacity(0.38))
            }
        }
    }

    // MARK: - Derived

    /// The fan posters in back→front order. The model has a single poster,
    /// so a populated poster fans as a 3-deep deck for depth; a missing
    /// poster fans generated gradient tiles. Capped at three (§5.6).
    private var fanPosters: [FanPoster] {
        if let url = collection.posterUrl, !url.isEmpty {
            return Array(repeating: .artwork(url: url, thumbhash: collection.posterThumbhash), count: 3)
        }
        return Array(repeating: .placeholder, count: 3)
    }

    /// `12 MOVIES`-style caps count (§5.6). Uses the collection's content
    /// noun when the type is known, else the neutral `ITEMS`.
    private var countText: String? {
        guard let count = collection.itemCount, count > 0 else { return nil }
        return "\(count) \(countNoun(for: count))".uppercased()
    }

    private func countNoun(for count: Int) -> String {
        let plural = count != 1
        switch collection.collectionType?.lowercased() {
        case "movie", "movies":
            return plural ? "movies" : "movie"
        case "series", "show", "shows", "tvshows":
            return plural ? "shows" : "show"
        case "album", "albums":
            return plural ? "albums" : "album"
        case "audiobook", "audiobooks", "book", "books":
            return plural ? "books" : "book"
        default:
            return plural ? "items" : "item"
        }
    }

    private var accessibilityLabel: String {
        var label = "\(collection.name), collection"
        if let count = collection.itemCount, count > 0 {
            label += ", \(count) \(count == 1 ? "item" : "items")"
        }
        return label
    }

    /// Stable hue for the generated fan when no poster exists — same
    /// derivation the poster collection cards use so a card looks identical
    /// whether it appears in the row or the grid.
    private var hue: Double {
        var hasher = Hasher()
        hasher.combine(collection.id)
        let raw = UInt(bitPattern: hasher.finalize())
        return Double(raw % 360) / 360.0
    }

    private enum FanPoster {
        case artwork(url: String, thumbhash: String?)
        case placeholder
    }
}

// MARK: - Focus button style

/// Fan-card focus visual: native-card-equivalent scale 1.05 + drop shadow
/// (§5.6 "identical to TVMediaCard"), with the system halo suppressed since
/// the surface draws its own 2 px white border. Honors reduce-motion by
/// holding scale at 1.0.
private struct TVFanCardButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        TVFanCardButtonBody(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct TVFanCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat

    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(scale)
            .shadow(
                color: .black.opacity(isFocused ? 0.5 : 0.0),
                radius: isFocused ? 20 : 0,
                y: isFocused ? 10 : 0
            )
            .focusEffectDisabled()
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: configuration.isPressed)
    }

    private var scale: CGFloat {
        let base: CGFloat = isFocused && !reduceMotion ? 1.05 : 1.0
        return configuration.isPressed ? base * 0.97 : base
    }
}

private extension View {
    /// Binds the fan card to a parent row's `@FocusState` so the row can
    /// route d-pad-entry default focus onto this specific card; no-op when
    /// the row doesn't manage focus. Mirrors `TVMediaCard.applyRailFocus`.
    @ViewBuilder
    func applyFanFocusBinding(_ binding: FocusState<String?>.Binding?, contentId: String?) -> some View {
        if let binding, let contentId {
            self.focused(binding, equals: contentId)
        } else {
            self
        }
    }
}
#endif
