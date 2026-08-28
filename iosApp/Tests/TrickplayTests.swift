import XCTest
@testable import Prairie

final class TrickplayTests: XCTestCase {
    private func sampleTrickplay(
        interval: Double = 10,
        columns: Int = 10,
        rows: Int = 10,
        width: Int = 320,
        height: Int = 180,
        thumbnailCount: Int = 250,
        sheetIndexes: [Int] = [0, 1, 2]
    ) -> VersionTrickplay {
        VersionTrickplay(
            intervalSeconds: interval,
            width: width,
            height: height,
            tileColumns: columns,
            tileRows: rows,
            thumbnailCount: thumbnailCount,
            sheets: sheetIndexes.map {
                VersionTrickplaySheet(index: $0, url: "https://cdn.example.com/tp/\($0).webp")
            }
        )
    }

    func testResolveTileUsesDefaultsAndSheetMath() {
        let tp = sampleTrickplay()
        // 125s / 10s = tile 12 → sheet 0, local 12 → col 2, row 1
        let tile = Trickplay.resolveTile(tp, seconds: 125)
        XCTAssertEqual(tile?.url, "https://cdn.example.com/tp/0.webp")
        XCTAssertEqual(tile?.column, 2)
        XCTAssertEqual(tile?.row, 1)
        XCTAssertEqual(tile?.width, 320)
        XCTAssertEqual(tile?.height, 180)
        XCTAssertEqual(tile?.columns, 10)
        XCTAssertEqual(tile?.rows, 10)
    }

    func testResolveTileCrossesSheetBoundary() {
        let tp = sampleTrickplay()
        // tilesPerSheet = 100; 1050s → tile 105 → sheet 1, local 5 → col 5, row 0
        let tile = Trickplay.resolveTile(tp, seconds: 1050)
        XCTAssertEqual(tile?.url, "https://cdn.example.com/tp/1.webp")
        XCTAssertEqual(tile?.column, 5)
        XCTAssertEqual(tile?.row, 0)
    }

    func testResolveTileClampsToLastThumbnail() {
        let tp = sampleTrickplay(thumbnailCount: 5)
        let tile = Trickplay.resolveTile(tp, seconds: 9_999)
        XCTAssertEqual(tile?.column, 4)
        XCTAssertEqual(tile?.row, 0)
        XCTAssertEqual(tile?.url, "https://cdn.example.com/tp/0.webp")
    }

    func testResolveTileReturnsNilWithoutSheetsOrCount() {
        XCTAssertNil(Trickplay.resolveTile(nil, seconds: 10))
        XCTAssertNil(
            Trickplay.resolveTile(
                sampleTrickplay(thumbnailCount: 0),
                seconds: 10
            )
        )
        var missingSheet = sampleTrickplay(sheetIndexes: [1])
        // Tile 0 lives on sheet 0, which is absent.
        XCTAssertNil(Trickplay.resolveTile(missingSheet, seconds: 0))
        missingSheet.sheets = [VersionTrickplaySheet(index: 0, url: "   ")]
        XCTAssertNil(Trickplay.resolveTile(missingSheet, seconds: 0))
    }

    func testResolveTileAppliesServerDefaultsForZeroGeometry() {
        let tp = VersionTrickplay(
            intervalSeconds: 0,
            width: 0,
            height: 0,
            tileColumns: 0,
            tileRows: 0,
            thumbnailCount: 3,
            sheets: [VersionTrickplaySheet(index: 0, url: "https://cdn.example.com/a.webp")]
        )
        let tile = Trickplay.resolveTile(tp, seconds: 25)
        XCTAssertEqual(tile?.column, 2)
        XCTAssertEqual(tile?.width, Trickplay.defaultTileWidth)
        XCTAssertEqual(tile?.height, Int((Double(Trickplay.defaultTileWidth) * 9 / 16).rounded()))
        XCTAssertEqual(tile?.columns, Trickplay.defaultTileColumns)
        XCTAssertEqual(tile?.rows, Trickplay.defaultTileRows)
    }

    func testFileVersionDecodesTrickplay() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let version = try decoder.decode(FileVersion.self, from: Data("""
        {
          "file_id": 42,
          "trickplay": {
            "interval_seconds": 10,
            "width": 320,
            "height": 180,
            "tile_columns": 10,
            "tile_rows": 10,
            "thumbnail_count": 12,
            "sheets": [
              { "index": 0, "url": "https://cdn.example.com/0.webp" }
            ]
          }
        }
        """.utf8))
        XCTAssertEqual(version.trickplay?.thumbnailCount, 12)
        XCTAssertEqual(version.trickplay?.sheets.first?.url, "https://cdn.example.com/0.webp")
        let tile = Trickplay.resolveTile(version.trickplay, seconds: 35)
        XCTAssertEqual(tile?.column, 3)
        XCTAssertEqual(tile?.row, 0)
    }
}
