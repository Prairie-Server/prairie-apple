import XCTest
@testable import Prairie

final class DolbyVisionPolicyTests: XCTestCase {
    private let dvOn = DolbyVisionPolicy.Snapshot(
        dolbyVisionEnabled: true,
        preferProfile7HDR10Fallback: false
    )
    private let dvOnWithP7Fallback = DolbyVisionPolicy.Snapshot(
        dolbyVisionEnabled: true,
        preferProfile7HDR10Fallback: true
    )
    private let dvOff = DolbyVisionPolicy.Snapshot(
        dolbyVisionEnabled: false,
        preferProfile7HDR10Fallback: false
    )
    private let dvOffWithP7Fallback = DolbyVisionPolicy.Snapshot(
        dolbyVisionEnabled: false,
        preferProfile7HDR10Fallback: true
    )

    // MARK: - Profile 5 (no HDR10-compatible base layer)

    func testProfile5AlwaysResolvesToDolbyVision() {
        for snapshot in [dvOn, dvOnWithP7Fallback, dvOff, dvOffWithP7Fallback] {
            XCTAssertEqual(
                DolbyVisionPolicy.resolution(forProfile: 5, snapshot: snapshot),
                .dolbyVision
            )
        }
    }

    // MARK: - Profile 7 precedence

    func testProfile7PlaysDolbyVisionByDefault() {
        XCTAssertEqual(
            DolbyVisionPolicy.resolution(forProfile: 7, snapshot: dvOn),
            .dolbyVision
        )
    }

    func testProfile7HonorsFallbackToggleWhileDolbyVisionOn() {
        XCTAssertEqual(
            DolbyVisionPolicy.resolution(forProfile: 7, snapshot: dvOnWithP7Fallback),
            .profile7HDR10Fallback
        )
    }

    func testDolbyVisionOffSupersedesProfile7FallbackToggle() {
        // Both fallback-toggle states must collapse to the same disabled
        // resolution — DV off wins, the P7 toggle is moot.
        XCTAssertEqual(
            DolbyVisionPolicy.resolution(forProfile: 7, snapshot: dvOff),
            .dolbyVisionDisabled
        )
        XCTAssertEqual(
            DolbyVisionPolicy.resolution(forProfile: 7, snapshot: dvOffWithP7Fallback),
            .dolbyVisionDisabled
        )
    }

    // MARK: - Base-layer-compatible profiles

    func testCompatibleProfilesFollowTheSetting() {
        for profile in [4, 8, 9, 10] {
            XCTAssertEqual(
                DolbyVisionPolicy.resolution(forProfile: profile, snapshot: dvOn),
                .dolbyVision,
                "profile \(profile)"
            )
            XCTAssertEqual(
                DolbyVisionPolicy.resolution(forProfile: profile, snapshot: dvOff),
                .dolbyVisionDisabled,
                "profile \(profile)"
            )
        }
    }

    // MARK: - Claims

    func testOnlyDisabledResolutionClearsDolbyVisionClaim() {
        XCTAssertTrue(DolbyVisionPolicy.claimsDolbyVisionOutput(.dolbyVision))
        XCTAssertTrue(DolbyVisionPolicy.claimsDolbyVisionOutput(.profile7HDR10Fallback))
        XCTAssertFalse(DolbyVisionPolicy.claimsDolbyVisionOutput(.dolbyVisionDisabled))
    }

    // MARK: - Compat-engine routing integration

    func testDecideRoutingStripsProfile8WhenDolbyVisionOff() {
        let config = makeConfig(profile: 8, compatId: 1)
        assertRouting(
            DolbyVisionFormat.decideRouting(config, policy: dvOff),
            isStrippedHdr10: true
        )
    }

    func testDecideRoutingKeepsProfile8NativeWhenDolbyVisionOn() {
        let config = makeConfig(profile: 8, compatId: 1)
        if case .native(let boxKey, _, _) = DolbyVisionFormat.decideRouting(config, policy: dvOn) {
            XCTAssertEqual(boxKey, "dvcC")
        } else {
            XCTFail("expected .native routing for profile 8 with Dolby Vision on")
        }
    }

    func testDecideRoutingKeepsProfile5PassthroughWhenDolbyVisionOff() {
        let config = makeConfig(profile: 5, compatId: 0)
        if case .p5Passthrough = DolbyVisionFormat.decideRouting(config, policy: dvOff) {
            // expected — the setting cannot apply to profile 5
        } else {
            XCTFail("expected .p5Passthrough routing for profile 5 regardless of the setting")
        }
    }

    func testDecideRoutingStillStripsProfile7RegardlessOfSetting() {
        let config = makeConfig(profile: 7, compatId: 1)
        assertRouting(DolbyVisionFormat.decideRouting(config, policy: dvOn), isStrippedHdr10: true)
        assertRouting(DolbyVisionFormat.decideRouting(config, policy: dvOff), isStrippedHdr10: true)
    }

    // MARK: - Helpers

    private func makeConfig(profile: UInt8, compatId: UInt8) -> DolbyVisionFormat.Config {
        DolbyVisionFormat.Config(
            versionMajor: 1,
            versionMinor: 0,
            profile: profile,
            level: 6,
            rpuPresent: true,
            elPresent: false,
            blPresent: true,
            compatId: compatId
        )
    }

    private func assertRouting(
        _ routing: DolbyVisionFormat.Routing,
        isStrippedHdr10: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .strippedHdr10 = routing {
            XCTAssertTrue(isStrippedHdr10, "unexpected .strippedHdr10", file: file, line: line)
        } else {
            XCTAssertFalse(isStrippedHdr10, "expected .strippedHdr10, got \(routing)", file: file, line: line)
        }
    }
}
