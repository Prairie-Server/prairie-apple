import Foundation

/// Sprite-sheet metadata for seek scrubbing, matching prairie-server
/// `VersionTrickplay` / web `PlayerTrickplay`.
struct VersionTrickplay: Codable, Hashable, Equatable {
    var intervalSeconds: Double
    var width: Int
    var height: Int
    var tileColumns: Int
    var tileRows: Int
    var thumbnailCount: Int
    var sheets: [VersionTrickplaySheet]
}

struct VersionTrickplaySheet: Codable, Hashable, Equatable {
    var index: Int
    var url: String
}

/// One resolved tile within a trickplay sprite sheet, ready for cropping.
struct TrickplayTilePreview: Equatable {
    let url: String
    let width: Int
    let height: Int
    let column: Int
    let row: Int
    let columns: Int
    let rows: Int
}

/// Sprite-sheet math mirroring web `resolveTrickplayTile` and
/// `internal/trickplay/math.go` defaults (10s, 320px, 10×10).
enum Trickplay {
    static let defaultIntervalSeconds: Double = 10
    static let defaultTileWidth = 320
    static let defaultTileColumns = 10
    static let defaultTileRows = 10

    static func resolveTile(
        _ trickplay: VersionTrickplay?,
        seconds: Double
    ) -> TrickplayTilePreview? {
        guard let trickplay,
              trickplay.thumbnailCount > 0,
              !trickplay.sheets.isEmpty else {
            return nil
        }

        let interval = trickplay.intervalSeconds > 0
            ? trickplay.intervalSeconds
            : defaultIntervalSeconds
        let columns = trickplay.tileColumns > 0
            ? trickplay.tileColumns
            : defaultTileColumns
        let rows = trickplay.tileRows > 0
            ? trickplay.tileRows
            : defaultTileRows
        let width = trickplay.width > 0
            ? trickplay.width
            : defaultTileWidth
        let height = trickplay.height > 0
            ? trickplay.height
            : Int((Double(width) * 9.0 / 16.0).rounded())

        let tilesPerSheet = max(1, columns * rows)
        let maxIndex = max(0, trickplay.thumbnailCount - 1)
        let tileIndex = min(max(0, Int(floor(seconds / interval))), maxIndex)
        let sheetIndex = tileIndex / tilesPerSheet
        guard let sheet = trickplay.sheets.first(where: { $0.index == sheetIndex }),
              !sheet.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let local = tileIndex % tilesPerSheet
        let column = local % columns
        let row = local / columns
        return TrickplayTilePreview(
            url: sheet.url,
            width: width,
            height: height,
            column: column,
            row: row,
            columns: columns,
            rows: rows
        )
    }
}
