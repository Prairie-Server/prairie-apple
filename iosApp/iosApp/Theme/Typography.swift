import SwiftUI

extension Font {
    #if os(tvOS)

    // tvOS is viewed from ~10 feet away, so all typography is scaled up
    // roughly 2.3x from iOS. tvOS has no user text-size preference, so fixed
    // point sizes are used to keep proportions stable across screens.

    /// Hero title overlaid on backdrop — massive on TV (76pt heavy)
    static let prairieHeroTitle = Font.system(size: 76, weight: .heavy).leading(.tight)

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

    /// Hero title overlaid on backdrop
    static let prairieHeroTitle = Font.largeTitle.bold().leading(.tight)

    /// Large screen titles — "Discover", "TV Shows"
    static let prairieTitle = Font.title3.bold()

    /// Section headlines — "Continue Watching"
    static let prairieHeadline = Font.headline

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
}
