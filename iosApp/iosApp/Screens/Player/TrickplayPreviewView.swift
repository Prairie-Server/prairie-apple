import SwiftUI
import NukeUI

/// Cropped sprite-sheet tile used in scrub previews on iOS and tvOS.
struct TrickplayTileImage: View {
    let tile: TrickplayTilePreview
    var displayWidth: CGFloat = 176

    private var displayHeight: CGFloat {
        guard tile.width > 0 else { return displayWidth * 9 / 16 }
        return displayWidth * CGFloat(tile.height) / CGFloat(tile.width)
    }

    var body: some View {
        let sheetWidth = displayWidth * CGFloat(max(tile.columns, 1))
        let sheetHeight = displayHeight * CGFloat(max(tile.rows, 1))
        Color.clear
            .frame(width: displayWidth, height: displayHeight)
            .overlay(alignment: .topLeading) {
                LazyImage(url: URL(string: tile.url)) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .interpolation(.high)
                            .frame(width: sheetWidth, height: sheetHeight)
                            .offset(
                                x: -CGFloat(tile.column) * displayWidth,
                                y: -CGFloat(tile.row) * displayHeight
                            )
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
            }
            .clipped()
    }
}

/// Shared scrub preview chrome: trickplay tile (preferred), chapter still
/// fallback, time readout, and optional chapter title.
struct ScrubPreviewBubble: View {
    let time: Double
    var trickplay: VersionTrickplay? = nil
    var chapterThumbnailURL: String? = nil
    var chapterTitle: String? = nil
    var compact: Bool = false

    private var tile: TrickplayTilePreview? {
        Trickplay.resolveTile(trickplay, seconds: time)
    }

    private var previewWidth: CGFloat { compact ? 160 : 176 }

    var body: some View {
        VStack(spacing: compact ? 4 : 6) {
            if let tile {
                TrickplayTileImage(tile: tile, displayWidth: previewWidth)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            } else if let chapterThumbnailURL,
                      !chapterThumbnailURL.isEmpty {
                CachedAsyncImage(
                    url: chapterThumbnailURL,
                    targetSize: CGSize(width: previewWidth, height: previewWidth * 9 / 16),
                    contentMode: .fill,
                    placeholderStyle: .clear
                )
                .frame(width: previewWidth, height: previewWidth * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
            }

            Text(PlayerTimeFormatter.formatHMS(time))
                .font(.system(size: compact ? 17 : 19, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()

            if let chapterTitle, !chapterTitle.isEmpty {
                Text(chapterTitle)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 8 : 10)
        .prairiePlayerGlass(in: RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous))
        .fixedSize()
    }
}
