import XCTest
import Foundation
@testable import Silo

final class LibraryVisibilityTests: XCTestCase {
    func testLibrariesResponseOnlyIncludesSupportedAppleLibraryTypes() {
        let json = """
        [
          { "id": 1, "name": "Movies", "type": "movies" },
          { "id": 2, "name": "Series", "type": "series" },
          { "id": 3, "name": "Audiobooks", "type": "audiobooks" },
          { "id": 4, "name": "Music", "type": "music" },
          { "id": 5, "name": "Ebooks", "type": "ebooks" },
          { "id": 6, "name": "Comics", "type": "comics" },
          { "id": 7, "name": "Podcasts", "type": "podcasts" }
        ]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try! decoder.decode(LibrariesResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.libraries.map(\.id), [1, 2, 3])
    }

    func testLibraryVisibilityUsesExplicitAudiobookLibraryTypesOnly() {
        XCTAssertTrue(SiloMediaType.isSupportedLibrary("audiobook"))
        XCTAssertTrue(SiloMediaType.isSupportedLibrary("audiobooks"))
        XCTAssertFalse(SiloMediaType.isSupportedLibrary("book"))
        XCTAssertFalse(SiloMediaType.isSupportedLibrary("books"))
    }
}
