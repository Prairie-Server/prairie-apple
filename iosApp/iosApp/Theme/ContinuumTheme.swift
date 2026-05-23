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
}
