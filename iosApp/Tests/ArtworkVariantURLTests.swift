import XCTest
@testable import Prairie

final class ArtworkVariantURLTests: XCTestCase {
    override func tearDown() {
        ImageFormats.resetForTests()
        super.tearDown()
    }

    func testRewritesWebPObjectKeysToAVIF() {
        XCTAssertEqual(
            ArtworkVariantURL.webPAVIFSibling(of: "library/1/poster/original.abc123.webp"),
            "library/1/poster/original.abc123.avif"
        )
        XCTAssertEqual(ArtworkVariantURL.webPAVIFSibling(of: "original.webp"), "original.avif")
    }

    func testRewritesWebPObjectKeysToPNG() {
        XCTAssertEqual(
            ArtworkVariantURL.webPPNGSibling(of: "library/1/poster/original.abc123.webp"),
            "library/1/poster/original.abc123.png"
        )
    }

    func testPreservesQueryStringsOnAbsoluteURLs() {
        XCTAssertEqual(
            ArtworkVariantURL.webPAVIFSibling(
                of: "https://cdn.example.com/art/original.rev.webp?X-Amz-Signature=abc"
            ),
            "https://cdn.example.com/art/original.rev.avif?X-Amz-Signature=abc"
        )
        XCTAssertEqual(
            ArtworkVariantURL.webPPNGSibling(
                of: "https://cdn.example.com/art/original.rev.webp?X-Amz-Signature=abc"
            ),
            "https://cdn.example.com/art/original.rev.png?X-Amz-Signature=abc"
        )
    }

    func testReturnsNilForNonWebPInputs() {
        XCTAssertNil(ArtworkVariantURL.webPAVIFSibling(of: "poster.jpg"))
        XCTAssertNil(ArtworkVariantURL.webPPNGSibling(of: "https://cdn.example.com/art/original.png"))
        XCTAssertNil(ArtworkVariantURL.webPAVIFSibling(of: ""))
        XCTAssertNil(ArtworkVariantURL.webPAVIFSibling(of: "   "))
    }

    func testCandidatesFollowConfiguredPreference() {
        ImageFormats.configure(["avif", "webp", "png"])
        XCTAssertEqual(
            ArtworkVariantURL.candidates(for: "poster.webp"),
            ["poster.avif", "poster.webp", "poster.png"]
        )
        ImageFormats.configure(["webp", "png"])
        XCTAssertEqual(
            ArtworkVariantURL.candidates(for: "poster.webp"),
            ["poster.webp", "poster.png"]
        )
        XCTAssertEqual(ArtworkVariantURL.candidates(for: "poster.jpg"), ["poster.jpg"])
    }

    func testPreferredFallsBackToOriginal() {
        ImageFormats.configure(["avif", "webp", "png"])
        XCTAssertEqual(ArtworkVariantURL.preferred("poster.jpg"), "poster.jpg")
        XCTAssertEqual(ArtworkVariantURL.preferred("poster.webp"), "poster.avif")
        ImageFormats.configure(["webp", "png"])
        XCTAssertEqual(ArtworkVariantURL.preferred("poster.webp"), "poster.webp")
    }

    func testExtensionMatchIsCaseInsensitive() {
        XCTAssertEqual(ArtworkVariantURL.webPAVIFSibling(of: "poster.WEBP"), "poster.avif")
        XCTAssertEqual(ArtworkVariantURL.webPPNGSibling(of: "poster.WEBP"), "poster.png")
    }

    func testImageFormatsHeaderValue() {
        ImageFormats.configure(["avif", "webp", "png"])
        XCTAssertEqual(ImageFormats.headerValue, "avif,webp,png")
    }

    func testWidthVariantRewritesPrairieSignedArtwork() {
        let signed = "/artwork/tmdb/movies/550/poster/w500.rev.webp?expires=123&sig=abc"
        XCTAssertEqual(
            ArtworkVariantURL.widthVariant(of: signed, width: 200),
            "/artwork/tmdb/movies/550/poster/w200.rev.webp?expires=123&sig=abc"
        )
        XCTAssertEqual(
            ArtworkVariantURL.widthVariant(of: signed, width: 300),
            "/artwork/tmdb/movies/550/poster/w300.rev.webp?expires=123&sig=abc"
        )
    }

    func testWidthVariantSkipsThirdPartySignaturesAndSignedOriginal() {
        XCTAssertNil(
            ArtworkVariantURL.widthVariant(
                of: "https://cdn.example.com/art/w300.webp?X-Amz-Signature=abc",
                width: 500
            )
        )
        XCTAssertNil(
            ArtworkVariantURL.widthVariant(
                of: "/artwork/tmdb/movies/550/poster/original.rev.webp?expires=123&sig=abc",
                width: 300
            )
        )
    }

    func testPreferredPosterWidthMatchesCardPixelBudget() {
        // iOS poster card 120pt @2x → 240px → w300
        XCTAssertEqual(ArtworkVariantURL.preferredPosterWidth(forPixels: 240), 300)
        // tvOS poster card 260pt @1x → 260px → w300
        XCTAssertEqual(ArtworkVariantURL.preferredPosterWidth(forPixels: 260), 300)
        // tvOS @2x → 520px → w500
        XCTAssertEqual(ArtworkVariantURL.preferredPosterWidth(forPixels: 520), 500)
        XCTAssertEqual(ArtworkVariantURL.preferredPosterWidth(forPixels: 120), 200)
    }

    func testCandidatesApplyWidthBeforeFormat() {
        ImageFormats.configure(["webp", "png"])
        let signed = "/artwork/tmdb/movies/550/poster/w500.rev.webp?expires=123&sig=abc"
        XCTAssertEqual(
            ArtworkVariantURL.candidates(for: signed, targetWidthPoints: 120, scale: 2),
            [
                "/artwork/tmdb/movies/550/poster/w300.rev.webp?expires=123&sig=abc",
                "/artwork/tmdb/movies/550/poster/w300.rev.png?expires=123&sig=abc",
            ]
        )
    }
}
