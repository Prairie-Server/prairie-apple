import XCTest
import Foundation
@testable import Silo

final class DecodeFailureRecoveryPolicyTests: XCTestCase {
    func testH264BadDataUsesRecoveryBeforeTerminalRejection() {
        XCTAssertTrue(
            DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -12909,
                codec: .h264,
                attempts: 0,
                maxAttempts: 2
            ),
            "H.264 kVTVideoDecoderBadDataErr should spend a bounded resync attempt before terminal rejection"
        )
    }

    func testH264BadDataStopsRecoveringAfterAttemptBudget() {
        XCTAssertFalse(
            DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -12909,
                codec: .h264,
                attempts: 2,
                maxAttempts: 2
            ),
            "H.264 bad-data recovery must stop after the attempt budget is exhausted"
        )
    }

    func testOtherH264ErrorsDoNotUseBurstRecovery() {
        XCTAssertFalse(
            DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -12903,
                codec: .h264,
                attempts: 0,
                maxAttempts: 2
            ),
            "Only bad-data decode bursts should use the discontinuity resync path"
        )
    }

    func testH264MalfunctionStatusUsesRecovery() {
        XCTAssertTrue(
            DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -8969,
                codec: .h264,
                attempts: 0,
                maxAttempts: 2
            ),
            "H.264 -8969 (compressed-sample rejection) is a bad-data burst and should resync"
        )
        XCTAssertFalse(
            DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -8969,
                codec: .hevc,
                attempts: 0,
                maxAttempts: 2
            ),
            "-8969 is an H.264-only bad-data status; HEVC must not treat it as a resync trigger"
        )
    }

    func testHEVCBadDataUsesRecoveryBeforeTerminalRejection() {
        XCTAssertTrue(
            DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -12909,
                codec: .hevc,
                attempts: 0,
                maxAttempts: 2
            ),
            "HEVC kVTVideoDecoderBadDataErr should spend a bounded resync attempt before terminal rejection"
        )
    }

    func testHEVCBadDataStopsRecoveringAfterAttemptBudget() {
        XCTAssertFalse(
            DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -12909,
                codec: .hevc,
                attempts: 2,
                maxAttempts: 2
            ),
            "HEVC bad-data recovery must stop after the attempt budget is exhausted"
        )
    }

    func testOtherHEVCErrorsDoNotUseBurstRecovery() {
        XCTAssertFalse(
            DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -12903,
                codec: .hevc,
                attempts: 0,
                maxAttempts: 2
            ),
            "Only HEVC bad-data decode bursts should use the discontinuity resync path"
        )
    }
}
