import Foundation
import ImageIO
import Nuke
import UniformTypeIdentifiers
import XCTest
@testable import Prairie

final class ServerTrickplayTests: XCTestCase {
    private func manifest(count: Int = 250, columns: Int64 = 10, sheets: [(Int, String)]? = nil) throws -> ServerTrickplay {
        let sheetList = (sheets ?? [(1, "/api/v2/images/s1?sig=b"), (0, "/api/v2/images/s0?sig=a"), (2, "/api/v2/images/s2?sig=c")])
            .map { #"{"index":\#($0.0),"url":"\#($0.1)"}"# }
            .joined(separator: ",")
        let json = #"""
        {"file_id":"42","interval_ms":10000,"thumbnail_width":320,"thumbnail_height":180,
         "tile_columns":\#(columns),"tile_rows":10,"thumbnail_count":\#(count),
         "sheets":[\#(sheetList)],"expires_at":"2026-01-02T03:04:05.000Z"}
        """#
        let decoder = HTTPClient.makeJSONDecoder(artworkServerURL: URL(string: "https://prairie.example:8090/api/v2/watch/movie:x/trickplay"))
        return try ServerTrickplay(v2: decoder.decode(APIv2CatalogRead.WatchTrickplay.self, from: Data(json.utf8)))
    }

    func testDecodesSheetsInIndexOrderAgainstTheServerOrigin() throws {
        let trickplay = try manifest()
        XCTAssertEqual(trickplay.fileId, 42)
        XCTAssertEqual(trickplay.interval, 10)
        XCTAssertEqual(trickplay.sheetURLs.map(\.absoluteString), [
            "https://prairie.example:8090/api/v2/images/s0?sig=a",
            "https://prairie.example:8090/api/v2/images/s1?sig=b",
            "https://prairie.example:8090/api/v2/images/s2?sig=c",
        ])
    }

    func testTileCoversTheWholeFileAndClampsToTheLastThumbnail() throws {
        let trickplay = try manifest()
        XCTAssertEqual(trickplay.tile(atSourceTime: 0), .init(sheet: 0, rect: CGRect(x: 0, y: 0, width: 320, height: 180)))
        // Thumbnail 123 = sheet 1, cell 23: column 3, row 2.
        XCTAssertEqual(trickplay.tile(atSourceTime: 1235), .init(sheet: 1, rect: CGRect(x: 960, y: 360, width: 320, height: 180)))
        // Past the end shows thumbnail 249 = sheet 2, cell 49.
        XCTAssertEqual(trickplay.tile(atSourceTime: 99_999), .init(sheet: 2, rect: CGRect(x: 2880, y: 720, width: 320, height: 180)))
        XCTAssertEqual(trickplay.tile(atSourceTime: 1e300)?.sheet, 2)
        XCTAssertNil(trickplay.tile(atSourceTime: -1))
        XCTAssertNil(trickplay.tile(atSourceTime: .nan))
    }

    func testRejectsAManifestWhoseSheetsDoNotHoldEveryThumbnail() {
        XCTAssertThrowsError(try manifest(count: 350))
        XCTAssertThrowsError(try manifest(sheets: [(0, "/a"), (1, "/b"), (2, "ftp://x/c")]))
    }

    func testRejectsGeometryThatOverflows() {
        XCTAssertThrowsError(try manifest(count: 1, columns: .max, sheets: [(0, "/a")]))
    }
}

/// Sheets load through the shared artwork pipeline, pointed here at a stub
/// server. Each sheet is 2 x 1 thumbnails of 20 x 20 pixels.
final class ServerTrickplaySheetsTests: XCTestCase {
    private let stub = StubURLProtocol.Handler()
    private var previousPipeline: ImagePipeline?

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        stub.install(into: configuration)
        previousPipeline = ImagePipeline.shared
        ImagePipeline.shared = ImagePipeline { $0.dataLoader = DataLoader(configuration: configuration) }
    }

    override func tearDown() {
        if let previousPipeline { ImagePipeline.shared = previousPipeline }
        super.tearDown()
    }

    private func manifest(signature: String, columns: Int = 2, expiresIn: TimeInterval = 3600) -> ServerTrickplay {
        let count = 4
        return ServerTrickplay(
            fileId: 42, interval: 10, thumbnailWidth: 20, thumbnailHeight: 20,
            columns: columns, rows: 1, count: count,
            sheetURLs: (0...(count - 1) / columns).map {
                URL(string: "https://trickplay-tests.example/sheets/\($0).jpg?sig=\(signature)")!
            },
            expiresAt: Date(timeIntervalSinceNow: expiresIn)
        )
    }

    private func serveSheets() {
        stub.route(StubURLProtocol.any) { _ in .init(status: 200, headers: ["Content-Type": "image/png"], body: Self.sheet) }
    }

    private func requests(forSheet sheet: Int) -> [StubURLProtocol.Request] {
        stub.requests.filter { $0.path == "/sheets/\(sheet).jpg" }
    }

    private static let sheet: Data = {
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()

    func testPrefetchSkipsASheetAScrubAlreadyFetched() async {
        serveSheets()
        let sheets = ServerTrickplaySheets(manifest(signature: "a")) { nil }

        let thumbnail = await sheets.thumbnail(atSourceTime: 25)
        let held = await sheets.awaitSheet(atSourceTime: 25)
        await sheets.prefetch()

        XCTAssertEqual(thumbnail?.width, 20)
        XCTAssertTrue(held, "a held sheet lets a scrub that gave up on it ask again")
        XCTAssertEqual(requests(forSheet: 1).count, 1)
        XCTAssertEqual(requests(forSheet: 0).count, 1)
    }

    func testAFailingSheetIsNotRequestedForEveryScrub() async {
        stub.route(StubURLProtocol.any) { _ in .status(500) }
        let sheets = ServerTrickplaySheets(manifest(signature: "a")) { nil }

        for seconds in [0.0, 5, 12] {
            let thumbnail = await sheets.thumbnail(atSourceTime: seconds)
            XCTAssertNil(thumbnail)
        }

        XCTAssertEqual(requests(forSheet: 0).count, 1)
    }

    func testARefusedSheetRenewsTheManifestAndRetriesWithTheFreshURL() async {
        stub.route({ $0.query["sig"] == "old" }) { _ in .status(403) }
        serveSheets()
        let fresh = manifest(signature: "new")
        let sheets = ServerTrickplaySheets(manifest(signature: "old")) { fresh }

        let thumbnail = await sheets.thumbnail(atSourceTime: 0)

        XCTAssertNotNil(thumbnail)
        XCTAssertEqual(requests(forSheet: 0).map { $0.query["sig"] }, ["old", "new"])
    }

    func testARenewalWithANewLayoutReplacesTheSheets() async {
        serveSheets()
        // The previews were made again with four thumbnails across, so the
        // whole file now fits on one sheet.
        let regenerated = manifest(signature: "new", columns: 4)
        let sheets = ServerTrickplaySheets(manifest(signature: "old", expiresIn: -60)) { regenerated }

        _ = await sheets.thumbnail(atSourceTime: 25)
        let thumbnail = await sheets.thumbnail(atSourceTime: 25)

        XCTAssertNotNil(thumbnail)
        XCTAssertTrue(requests(forSheet: 1).isEmpty, "the old layout's second sheet is not fetched")
        XCTAssertEqual(stub.requests.map { $0.query["sig"] }, ["new"])
    }
}
