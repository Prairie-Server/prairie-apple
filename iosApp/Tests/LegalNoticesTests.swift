import XCTest
@testable import Prairie

/// Settings > About legal notices: the build's source link and the bundled
/// license texts behind Open Source Licenses.
final class LegalNoticesTests: XCTestCase {
    func testStampedReleaseArchiveIsTheSourceLink() {
        // Single-platform tags such as v1.4.0+ios arrive percent-encoded.
        for tag in ["v1.0.0", "v1.4.0%2Bios"] {
            let archive = "https://github.com/Prairie-Server/prairie-apple/releases/download/\(tag)/"
                + "Prairie-source-\(String(repeating: "a", count: 40)).tar.gz"

            XCTAssertEqual(PrairieLegalLinks.sourceURL(stamped: archive).absoluteString, archive)
        }
    }

    func testMissingOrForeignStampLinksTheRepository() {
        let stamps: [String?] = [
            nil,
            "",
            "$(PRAIRIE_SOURCE_URL)",
            "http://github.com/Prairie-Server/prairie-apple/releases/download/v1/a.tar.gz",
            "https://example.com/Prairie-Server/prairie-apple/releases/download/v1/a.tar.gz",
            "https://github.com/someone/prairie-apple/releases/download/v1/a.tar.gz",
            "https://github.com/Prairie-Server/prairie-apple-fork/releases/download/v1/a.tar.gz",
        ]

        for stamp in stamps {
            XCTAssertEqual(PrairieLegalLinks.sourceURL(stamped: stamp), PrairieLegalLinks.repository, stamp ?? "nil")
        }
    }

    /// Includes LICENSE and APPSTORE-EXCEPTION.md, which project.yml copies
    /// from the repository root rather than OpenSourceLicenses/.
    func testEveryAcknowledgementResourceIsBundled() {
        for resource in OpenSourceAcknowledgements.resources {
            XCTAssertNotNil(OpenSourceAcknowledgements.resourceURL(for: resource), resource.name)
        }
    }
}
