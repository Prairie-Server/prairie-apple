import Foundation

@main
struct DecodeFailureRecoveryPolicyTests {
    static func main() {
        testH264BadDataUsesRecoveryBeforeTerminalRejection()
        testH264BadDataStopsRecoveringAfterAttemptBudget()
        testOtherH264ErrorsDoNotUseBurstRecovery()
        print("DecodeFailureRecoveryPolicyTests: all passed")
    }

    private static func testH264BadDataUsesRecoveryBeforeTerminalRejection() {
        precondition(
            DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -12909,
                codec: .h264,
                attempts: 0,
                maxAttempts: 2
            ),
            "H.264 kVTVideoDecoderBadDataErr should spend a bounded resync attempt before terminal rejection"
        )
    }

    private static func testH264BadDataStopsRecoveringAfterAttemptBudget() {
        precondition(
            !DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -12909,
                codec: .h264,
                attempts: 2,
                maxAttempts: 2
            ),
            "H.264 bad-data recovery must stop after the attempt budget is exhausted"
        )
    }

    private static func testOtherH264ErrorsDoNotUseBurstRecovery() {
        precondition(
            !DecodeFailureRecoveryPolicy.shouldAttemptBurstResync(
                status: -12903,
                codec: .h264,
                attempts: 0,
                maxAttempts: 2
            ),
            "Only bad-data decode bursts should use the discontinuity resync path"
        )
    }
}
