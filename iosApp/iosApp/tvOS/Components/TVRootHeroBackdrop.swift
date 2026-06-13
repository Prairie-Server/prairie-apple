#if os(tvOS)
import SwiftUI

/// Page-level ambient hero backdrop for root tvOS screens.
///
/// Keeping this behind the whole page instead of inside the hero/marquee
/// gives the custom top menu, marquee, and rows one shared visual plane.
/// On Home and the library Browse landings the artwork tracks the
/// marquee's focused item (Skyline §5.4); Calendar and Recommendations
/// keep passing static (nil) artwork.
struct TVRootHeroBackdrop: View {
    let tintColor: Color
    let artworkURL: String?
    let artworkThumbhash: String?
    var isVisible: Bool = true
    /// Artwork/tint crossfade duration. Focus-marquee hosts pass the §4.2
    /// 240 ms swap; other surfaces keep the slower ambient default.
    var crossfadeDuration: Double = 0.55

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let fadeExtension: CGFloat = 420
    private let horizontalBleed: CGFloat = 380
    private let heroHeight: CGFloat = 760
    /// How far the blurred art is pushed toward the trailing edge so its
    /// focal mass sits right of the marquee text column (§5.4). Paired with
    /// `leadingReadabilityScrim`, which keeps the leading half dark so the
    /// title/meta/synopsis stay legible regardless of the focused art's
    /// colors. The bleed above absorbs the shift so no gap opens on the left.
    private let artHorizontalShift: CGFloat = 150

    var body: some View {
        ZStack(alignment: .top) {
            tintBackground

            if isVisible {
                backdropImage
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var tintBackground: some View {
        LinearGradient(
            stops: [
                .init(color: tintColor, location: 0.0),
                .init(color: tintColor.opacity(isVisible ? 0.55 : 0.0), location: 0.35),
                .init(color: .continuumBackground, location: 0.8),
                .init(color: .continuumBackground, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: crossfadeDuration), value: tintColor)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: isVisible)
    }

    @ViewBuilder
    private var backdropImage: some View {
        let totalHeight = heroHeight + fadeExtension

        GeometryReader { geometry in
            let visibleWidth = geometry.size.width
            let paintedWidth = visibleWidth + horizontalBleed

            Color.clear
                .frame(width: visibleWidth, height: totalHeight, alignment: .top)
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        if let artworkURL, !artworkURL.isEmpty {
                            AsyncImageView(
                                url: artworkURL,
                                thumbhash: artworkThumbhash,
                                targetSize: CGSize(width: paintedWidth, height: totalHeight),
                                contentMode: .fill
                            )
                            .id(artworkURL)
                            .frame(width: paintedWidth, height: totalHeight, alignment: .top)
                            .scaleEffect(1.04)
                            .blur(radius: 22)
                            // Push the focal mass off the leading text column;
                            // the bleed leaves the left edge covered.
                            .offset(x: artHorizontalShift)
                            .transition(
                                reduceMotion
                                    ? .identity
                                    : .opacity.animation(.easeInOut(duration: crossfadeDuration))
                            )

                            Rectangle()
                                .fill(Color.black.opacity(0.34))
                                .frame(width: paintedWidth, height: totalHeight)

                            LinearGradient(
                                colors: [.black.opacity(0.54), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: paintedWidth, height: 140, alignment: .top)

                            // Leading readability scrim. Visible-width (not
                            // the bled paint width) so the leading→trailing
                            // ramp maps to the screen: the marquee text column
                            // stays dark, the art breathes on the trailing side.
                            leadingReadabilityScrim
                                .frame(width: visibleWidth, height: totalHeight)
                        }
                    }
                    .frame(width: paintedWidth, height: totalHeight, alignment: .top)
                    .mask {
                        fadeMask
                            .frame(width: paintedWidth, height: totalHeight)
                    }
                }
        }
        .frame(height: totalHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: [.top, .horizontal])
    }

    /// Horizontal dark-to-clear ramp behind the marquee's leading text
    /// column (§5.4). The text spans roughly the leading half (safeArea.x
    /// 88 → synopsis cap 780), so the scrim holds full strength through the
    /// midline, then falls to clear by ~0.9 so the trailing art reads at the
    /// base 34% dim only. Stacks on that flat dim, so the leading edge lands
    /// near ~0.8 effective — a stable bed for white title + secondary text.
    private var leadingReadabilityScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.72), location: 0.0),
                .init(color: .black.opacity(0.6), location: 0.3),
                .init(color: .black.opacity(0.34), location: 0.52),
                .init(color: .black.opacity(0.08), location: 0.72),
                .init(color: .clear, location: 0.9),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.42),
                .init(color: Color.black.opacity(0.7), location: 0.66),
                .init(color: Color.black.opacity(0.25), location: 0.86),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
#endif
