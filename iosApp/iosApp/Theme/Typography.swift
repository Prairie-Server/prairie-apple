import SwiftUI

extension Font {
    #if os(tvOS)

    // tvOS is viewed from ~10 feet away, so all typography is scaled up
    // roughly 2.3x from iOS. tvOS has no user text-size preference, so fixed
    // point sizes are used to keep proportions stable across screens.

    /// Large screen titles — "Discover", "TV Shows" (48pt bold)
    static let prairieTitle = Font.system(size: 48, weight: .bold)

    /// Section headlines — "Continue Watching" (36pt semibold)
    static let prairieHeadline = Font.system(size: 36, weight: .semibold)

    /// Card titles and subheadlines (28pt semibold)
    static let prairieSubheadline = Font.system(size: 28, weight: .semibold)

    /// Movie/series names directly beneath artwork. Kept quieter than general
    /// subheadlines so dense eight-across rows remain readable rather than
    /// visually shouting over the posters.
    static let prairiePosterTitle = Font.system(size: 24, weight: .medium)

    /// Year, episode title, and other secondary poster-card metadata.
    static let prairiePosterMetadata = Font.system(size: 20, weight: .regular)

    /// Body text — descriptions, synopses (26pt regular)
    static let prairieBody = Font.system(size: 26)

    /// Captions and metadata (22pt regular)
    static let prairieCaption = Font.system(size: 22, weight: .regular)

    /// Smallest text — badges, episode numbers, tab labels (20pt regular)
    static let prairieSmall = Font.system(size: 20, weight: .regular)

    /// Numeric displays like PINs (64pt monospaced bold)
    static let prairiePIN = Font.system(size: 64, weight: .bold, design: .monospaced)

    #else

    #if os(macOS)
    // macOS text styles run about two points smaller than iOS, which left
    // page and row headings undersized in a desktop window. The Mac steps
    // both up one style.

    /// Large screen titles — "Discover", "TV Shows"
    static let prairieTitle = Font.title2.bold()

    /// Section headlines — "Continue Watching"
    static let prairieHeadline = Font.title3.weight(.semibold)

    /// Title of Home's featured hero.
    static let prairieHeroTitle = Font.system(size: 34, weight: .bold)
    #else
    /// Large screen titles — "Discover", "TV Shows"
    static let prairieTitle = Font.title3.bold()

    /// Section headlines — "Continue Watching"
    static let prairieHeadline = Font.headline
    #endif

    /// Card titles and subheadlines
    static let prairieSubheadline = Font.subheadline.bold()

    /// Body text — descriptions, synopses
    static let prairieBody = Font.body

    /// Captions and metadata
    static let prairieCaption = Font.caption

    /// Smallest text — badges, episode numbers, tab labels
    static let prairieSmall = Font.caption2

    /// Numeric displays like PINs
    static let prairiePIN = Font.largeTitle.monospaced().bold()

    #endif

    // MARK: - Card captions

    /// Title under a poster or still card. The Mac's cards are larger than
    /// the phone's, and its text styles smaller, so it steps the caption up.
    static var prairieCardTitle: Font {
        #if os(macOS)
        .body.weight(.semibold)
        #else
        prairieSubheadline
        #endif
    }

    /// Year, episode, or time-left line under a card title.
    static var prairieCardMetadata: Font {
        #if os(macOS)
        .callout
        #else
        prairieCaption
        #endif
    }
}

extension View {
    /// A system font with an exact point size that still follows Dynamic Type.
    /// `size` is the point size at the default (Large) text size; other sizes
    /// scale it the way `textStyle` scales, and an enclosing
    /// `.dynamicTypeSize(_:)` limit applies. Pick the text style whose default
    /// size is closest to `size`. Use this where a design needs a point size
    /// between the semantic styles; prefer a semantic font otherwise.
    func prairieScaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design? = nil,
        relativeTo textStyle: Font.TextStyle
    ) -> some View {
        modifier(PrairieScaledSystemFont(size: size, weight: weight, design: design, textStyle: textStyle))
    }
}

private struct PrairieScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design?

    init(size: CGFloat, weight: Font.Weight, design: Font.Design?, textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}
