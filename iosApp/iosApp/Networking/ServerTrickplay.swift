import CoreGraphics
import Foundation
import ImageIO

/// Seek-bar previews the server published for one file: sprite sheets of
/// thumbnails, one thumbnail per interval of source time. Unlike stills cut
/// from the player's cache, they cover the whole file before any of it has
/// been buffered.
struct ServerTrickplay: Equatable, Sendable {
    let fileId: Int
    /// Source time each thumbnail covers, in seconds.
    let interval: Double
    let thumbnailWidth: Int
    let thumbnailHeight: Int
    let columns: Int
    let rows: Int
    let count: Int
    /// One URL per sheet, in order. Each carries its own authorization.
    let sheetURLs: [URL]
    let expiresAt: Date

    struct Tile: Equatable {
        let sheet: Int
        /// The thumbnail's rectangle within its sheet, at full size.
        let rect: CGRect
    }

    enum InvalidManifest: Error {
        case geometry
        case sheets
    }

    /// The thumbnail shown for a source time, clamped to the last one.
    func tile(atSourceTime seconds: Double) -> Tile? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let position = seconds / interval
        let index = position >= Double(count - 1) ? count - 1 : Int(position)
        let perSheet = columns * rows
        let cell = index % perSheet
        return Tile(
            sheet: index / perSheet,
            rect: CGRect(
                x: (cell % columns) * thumbnailWidth,
                y: (cell / columns) * thumbnailHeight,
                width: thumbnailWidth,
                height: thumbnailHeight
            )
        )
    }

    /// Whether another manifest lays out the same thumbnails, so its sheet
    /// URLs can replace these ones.
    func hasSameLayout(as other: ServerTrickplay) -> Bool {
        fileId == other.fileId && interval == other.interval
            && thumbnailWidth == other.thumbnailWidth && thumbnailHeight == other.thumbnailHeight
            && columns == other.columns && rows == other.rows && count == other.count
            && sheetURLs.count == other.sheetURLs.count
    }
}
