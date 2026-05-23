#if os(tvOS)
import SwiftUI

/// Page-level ambient hero backdrop for root tvOS screens.
///
/// Keeping this behind the whole page instead of inside `FeaturedCarousel`
/// gives the custom top menu, hero, and rows one shared visual plane.
struct TVRootHeroBackdrop: View {
    let tintColor: Color
    let artworkURL: String?
    let artworkThumbhash: String?
    var isVisible: Bool = true

    private let fadeExtension: CGFloat = 420
    private let horizontalBleed: CGFloat = 320
    private let heroHeight: CGFloat = 760

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
        .animation(.easeInOut(duration: 0.55), value: tintColor)
        .animation(.easeInOut(duration: 0.24), value: isVisible)
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
                            .transition(.opacity.animation(.easeInOut(duration: 0.55)))

                            Rectangle()
                                .fill(Color.black.opacity(0.34))
                                .frame(width: paintedWidth, height: totalHeight)

                            LinearGradient(
                                colors: [.black.opacity(0.54), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: paintedWidth, height: 140, alignment: .top)
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
