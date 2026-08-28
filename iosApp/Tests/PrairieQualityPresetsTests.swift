import XCTest
@testable import Prairie

final class PrairieQualityPresetsTests: XCTestCase {

    func testPresetLookupByStoredPair() {
        XCTAssertEqual(PrairieQualityPresets.preset(resolution: "1080p", bitrateKbps: 10_000)?.id, "1080p-high")
        XCTAssertEqual(PrairieQualityPresets.preset(resolution: "auto", bitrateKbps: nil)?.id, "auto")
        XCTAssertNil(PrairieQualityPresets.preset(resolution: "1080p", bitrateKbps: 9_999))
        XCTAssertNil(PrairieQualityPresets.preset(resolution: "1080p", bitrateKbps: 0))
    }

    func testPresetLookupById() {
        XCTAssertEqual(PrairieQualityPresets.preset(id: "720p")?.label, "720p")
        XCTAssertNil(PrairieQualityPresets.preset(id: nil))
        XCTAssertNil(PrairieQualityPresets.preset(id: "missing"))
    }

    func testDescribeUsesPresetLabelWhenKnown() {
        XCTAssertEqual(PrairieQualityPresets.describe(resolution: "480p", bitrateKbps: 1_500), "480p")
        XCTAssertEqual(PrairieQualityPresets.describe(resolution: "auto", bitrateKbps: nil), "Auto")
    }

    func testDescribeFormatsCustomBitratePairs() {
        XCTAssertEqual(PrairieQualityPresets.describe(resolution: "1080p", bitrateKbps: 5_500), "1080p at 5.5 Mbps")
        XCTAssertEqual(PrairieQualityPresets.describe(resolution: "2160p", bitrateKbps: 12_000), "4K at 12 Mbps")
        XCTAssertEqual(PrairieQualityPresets.describe(resolution: "original", bitrateKbps: nil), "Original")
    }

    func testNormalizeResolutionHandlesLegacySpellings() {
        XCTAssertEqual(PrairieQualityPresets.normalizeResolution(nil), "auto")
        XCTAssertEqual(PrairieQualityPresets.normalizeResolution(""), "auto")
        XCTAssertEqual(PrairieQualityPresets.normalizeResolution("  AUTO  "), "auto")
        XCTAssertEqual(PrairieQualityPresets.normalizeResolution("original"), "original")
        XCTAssertEqual(PrairieQualityPresets.normalizeResolution("4k"), "2160p")
        XCTAssertEqual(PrairieQualityPresets.normalizeResolution("UHD"), "2160p")
        XCTAssertEqual(PrairieQualityPresets.normalizeResolution("1080p-high"), "1080p")
        XCTAssertEqual(PrairieQualityPresets.normalizeResolution("720p-8"), "720p")
        XCTAssertEqual(PrairieQualityPresets.normalizeResolution("not-a-resolution"), "auto")
    }

    func testAllPresetsExposeStableIds() {
        XCTAssertEqual(PrairieQualityPresets.all.count, 9)
        XCTAssertEqual(Set(PrairieQualityPresets.all.map(\.id)).count, 9)
        XCTAssertTrue(PrairieQualityPresets.all.allSatisfy { !$0.label.isEmpty && !$0.description.isEmpty })
    }
}
