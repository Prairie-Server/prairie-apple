import XCTest
@testable import Prairie

final class ArtworkURLTests: XCTestCase {
    func testRewritesWebPObjectKeysToAVIF() {
        XCTAssertEqual(
            ArtworkURL.webPAVIFSibling(of: "library/1/poster/original.abc123.webp"),
            "library/1/poster/original.abc123.avif"
        )
        XCTAssertEqual(ArtworkURL.webPAVIFSibling(of: "original.webp"), "original.avif")
    }

    func testRewritesWebPObjectKeysToPNG() {
        XCTAssertEqual(
            ArtworkURL.webPPNGSibling(of: "library/1/poster/original.abc123.webp"),
            "library/1/poster/original.abc123.png"
        )
    }

    func testPreservesQueryStringsOnAbsoluteURLs() {
        XCTAssertEqual(
            ArtworkURL.webPAVIFSibling(
                of: "https://cdn.example.com/art/original.rev.webp?X-Amz-Signature=abc"
            ),
            "https://cdn.example.com/art/original.rev.avif?X-Amz-Signature=abc"
        )
        XCTAssertEqual(
            ArtworkURL.webPPNGSibling(
                of: "https://cdn.example.com/art/original.rev.webp?X-Amz-Signature=abc"
            ),
            "https://cdn.example.com/art/original.rev.png?X-Amz-Signature=abc"
        )
    }

    func testReturnsNilForNonWebPInputs() {
        XCTAssertNil(ArtworkURL.webPAVIFSibling(of: "poster.jpg"))
        XCTAssertNil(ArtworkURL.webPPNGSibling(of: "https://cdn.example.com/art/original.png"))
        XCTAssertNil(ArtworkURL.webPAVIFSibling(of: ""))
        XCTAssertNil(ArtworkURL.webPAVIFSibling(of: "   "))
    }

    func testCandidatesOrderAVIFWebPPNG() {
        XCTAssertEqual(
            ArtworkURL.candidates(for: "poster.webp"),
            ["poster.avif", "poster.webp", "poster.png"]
        )
        XCTAssertEqual(ArtworkURL.candidates(for: "poster.jpg"), ["poster.jpg"])
    }

    func testPreferredFallsBackToOriginal() {
        XCTAssertEqual(ArtworkURL.preferred("poster.jpg"), "poster.jpg")
        XCTAssertEqual(ArtworkURL.preferred("poster.webp"), "poster.avif")
    }

    func testExtensionMatchIsCaseInsensitive() {
        XCTAssertEqual(ArtworkURL.webPAVIFSibling(of: "poster.WEBP"), "poster.avif")
        XCTAssertEqual(ArtworkURL.webPPNGSibling(of: "poster.WEBP"), "poster.png")
    }
}
