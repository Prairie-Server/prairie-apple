import SwiftUI

/// Central design token repository matching Plezy's mono theme.
/// On tvOS, spacing/radius tokens are scaled up to match 10-foot viewing distance.
struct ContinuumTheme {

    // MARK: - Platform scale

    #if os(tvOS)
    /// Uniform scale applied to tvOS — everything is ~2x bigger than iOS.
    static let scale: CGFloat = 2.0
    #else
    static let scale: CGFloat = 1.0
    #endif

    // MARK: - Corner Radii

    #if os(tvOS)
    /// Standard card/poster corner radius (12pt on tvOS, larger so focus rings read well)
    static let cornerRadius: CGFloat = 12
    /// Smaller elements like episode thumbnail corners
    static let smallCornerRadius: CGFloat = 8
    /// Card container radius
    static let cardCornerRadius: CGFloat = 18
    #else
    /// Standard card/poster corner radius (8pt — Plezy radiusSm)
    static let cornerRadius: CGFloat = 8
    /// Smaller elements like episode thumbnail corners (6pt)
    static let smallCornerRadius: CGFloat = 6
    /// Card container radius (14pt — Plezy CardTheme)
    static let cardCornerRadius: CGFloat = 14
    #endif

    /// Pill-shaped elements — use Capsule() instead of a fixed radius
    static let pillCornerRadius: CGFloat = 100

    // MARK: - Spacing

    #if os(tvOS)
    /// Base spacing unit — scaled up for TV
    static let spacing: CGFloat = 24
    /// Standard content padding
    static let padding: CGFloat = 48
    /// Compact padding
    static let smallPadding: CGFloat = 16
    /// Large section spacing
    static let largePadding: CGFloat = 60
    /// Screen safe-area padding — tvOS always wants overscan
    static let safePadding: CGFloat = 80
    #else
    /// Base spacing unit (12pt — Plezy space token)
    static let spacing: CGFloat = 12
    /// Standard content padding (16pt)
    static let padding: CGFloat = 16
    /// Compact padding (8pt)
    static let smallPadding: CGFloat = 8
    /// Large section spacing (24pt)
    static let largePadding: CGFloat = 24
    /// No extra overscan padding on iOS
    static let safePadding: CGFloat = 16
    #endif

    // MARK: - Elevation

    /// Card elevation — zero for Plezy-style flat cards
    static let cardElevation: CGFloat = 0

    // MARK: - Media Aspect Ratios

    /// Movie/show poster (2:3.3 — Plezy uses slightly taller posters)
    static let posterAspectRatio: CGFloat = 2.0 / 3.3

    /// Backdrop/banner image (16:9)
    static let backdropAspectRatio: CGFloat = 16.0 / 9.0

    /// Episode thumbnail (16:9)
    static let thumbnailAspectRatio: CGFloat = 16.0 / 9.0

    // MARK: - Media Card Dimensions

    #if os(tvOS)
    /// Poster card width in a media row
    static let posterCardWidth: CGFloat = 260
    /// Poster card height matching aspect ratio
    static let posterCardHeight: CGFloat = 390
    /// Episode/thumbnail card width
    static let thumbnailCardWidth: CGFloat = 360
    /// Episode/thumbnail card height
    static let thumbnailCardHeight: CGFloat = 200
    #else
    static let posterCardWidth: CGFloat = 120
    static let posterCardHeight: CGFloat = 198
    static let thumbnailCardWidth: CGFloat = 160
    static let thumbnailCardHeight: CGFloat = 90
    #endif

    /// Profile avatar size
    #if os(tvOS)
    static let profileAvatarSize: CGFloat = 160
    #else
    static let profileAvatarSize: CGFloat = 80
    #endif

    // MARK: - Animation Durations (Plezy mono_tokens)

    /// Fast — focus state changes, hover effects (120ms)
    static let fastDuration: Double = 0.12

    /// Normal — tab transitions, chip selection (200ms)
    static let normalDuration: Double = 0.20

    /// Slow — image crossfades, content reveals (300ms)
    static let slowDuration: Double = 0.30

    /// Standard transition duration
    static let animationDuration: Double = 0.20

    /// Standard spring animation
    static let springAnimation = Animation.spring(response: 0.35, dampingFraction: 0.85)

    #if os(tvOS)
    // MARK: - Skyline chrome metrics (tvOS)

    /// Skyline navigation chrome tokens (design guide §4–§5). Values are
    /// mockup pixels at 1920×1080, which render 1:1 as points on tvOS.
    enum Skyline {
        /// Root horizontal inset for chrome and content — `safeArea.x`.
        static let safeAreaX: CGFloat = 88
        /// Top bar offset from the screen's top edge — `safeArea.top`.
        static let barTopInset: CGFloat = 56
        /// Top bar row height.
        static let barHeight: CGFloat = 64
        /// Gap between tab capsules in the bar's center cluster.
        static let tabSpacing: CGFloat = 8
        static let tabLabelSize: CGFloat = 23
        static let tabPaddingHorizontal: CGFloat = 26
        static let tabPaddingVertical: CGFloat = 11
        /// Square hit target of the search button and the profile avatar.
        static let barIconSize: CGFloat = 52
        /// Gap between the search button and the avatar.
        static let barTrailingSpacing: CGFloat = 22
        static let wordmarkSize: CGFloat = 26
        /// Wordmark letter tracking — +0.34 em.
        static let wordmarkTracking: CGFloat = 26 * 0.34
        /// Bar opacity while focus is down in the content zone (§5.1).
        static let barDimmedOpacity: Double = 0.7

        /// Pill row offset from the screen top — 30 below the bar (§5.2).
        static let pillRowTopInset: CGFloat = 150
        static let pillSpacing: CGFloat = 12
        static let pillLabelSize: CGFloat = 19
        static let pillPaddingHorizontal: CGFloat = 22
        static let pillPaddingVertical: CGFloat = 9
        /// Right-aligned scope caption in the pill row.
        static let pillCaptionSize: CGFloat = 18

        /// Top inset for library-tab content that has no hero of its own
        /// (grids, chip clouds): clears the bar and the pill row.
        static let libraryContentTopInset: CGFloat = 216
        /// Extra top inset the featured hero needs on library tabs so its
        /// card deck starts below the pill row instead of under it.
        static let libraryHeroExtraTopInset: CGFloat = 88

        /// Anchored dropdown panel (§5.3/§5.8).
        static let dropdownWidth: CGFloat = 460
        static let dropdownCornerRadius: CGFloat = 22
        static let dropdownPadding: CGFloat = 14
        static let dropdownRowTextSize: CGFloat = 22
        static let dropdownHeaderSize: CGFloat = 14
        /// Panel top offset — anchored just under the bar.
        static let dropdownTopInset: CGFloat = 132

        // MARK: Focus marquee (§5.4/§5.5)

        /// Marquee content block top — Home (full-bleed) scale.
        static let marqueeTopHome: CGFloat = 218
        /// Marquee content block top — library (compact) scale.
        static let marqueeTopLibrary: CGFloat = 246
        /// Marquee content block width.
        static let marqueeContentWidth: CGFloat = 880
        static let marqueeTitleSizeHome: CGFloat = 84
        static let marqueeTitleSizeLibrary: CGFloat = 66
        static let marqueeMetaSizeHome: CGFloat = 20
        static let marqueeMetaSizeLibrary: CGFloat = 19
        static let marqueeSynopsisSize: CGFloat = 22
        /// Synopsis column cap (§4.1) — narrower than the content block.
        static let marqueeSynopsisMaxWidth: CGFloat = 780
        /// Cached server logo art caps in the marquee title slot. With
        /// rows paging one section at a time along the bottom of the
        /// screen, Home affords the full §5.4 cap; the library scale
        /// stays tighter because the pill row eats into its band. While
        /// a logo is shown the synopsis drops a line, like a wrapped
        /// title.
        static let marqueeLogoMaxWidth: CGFloat = 880
        static let marqueeLogoMaxHeightHome: CGFloat = 200
        static let marqueeLogoMaxHeightLibrary: CGFloat = 150
        /// Codec/HDR badge chip label size (§4.1).
        static let marqueeBadgeSize: CGFloat = 15
        /// Focus must rest this long before the marquee swaps (§4.2) —
        /// rolling through cards never thrashes backdrops.
        static let marqueeRestDebounceMilliseconds = 150
        /// Marquee text + backdrop crossfade duration (§4.2).
        static let marqueeCrossfadeDuration: Double = 0.24

        // MARK: Row band under the marquee (§5.7, revised)

        /// Top of the row band on Home. Rows page one section at a time
        /// in viewport-sized slots, bottom-aligned so the focused row
        /// sits at the bottom of the screen; the band must be tall
        /// enough for the tallest row (a full poster row ≈ 585).
        static let homeFirstRowTop: CGFloat = 535
        /// Top of the row band on a library Browse landing.
        static let libraryFirstRowTop: CGFloat = 510
        /// Dense poster card (§5.6) used on Browse landing rows so two
        /// rows + marquee fit above the fold.
        static let densePosterCardWidth: CGFloat = 208
    }
    #endif
}
