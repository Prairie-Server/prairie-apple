import XCTest
@testable import Silo

final class AVSyncLadderTests: XCTestCase {
    private let frameDuration = 1.0 / 24.0

    private func input(
        diff: Double,
        decoded: Int = 10,
        packets: Int = 100,
        wall: Double
    ) -> AVSyncLadder.Input {
        AVSyncLadder.Input(
            diffSeconds: diff,
            frameDurationSeconds: frameDuration,
            decodedFrameCount: decoded,
            packetCount: packets,
            wallNow: wall
        )
    }

    func testOnTimeFramesDoNothing() {
        var ladder = AVSyncLadder()
        XCTAssertEqual(ladder.evaluate(input(diff: 0, wall: 0)), .none)
        XCTAssertEqual(ladder.evaluate(input(diff: -frameDuration, wall: 1)), .none)
    }

    func testMildLatenessStaysAtRungZero() {
        var ladder = AVSyncLadder()
        // Behind the tick's drop threshold but above rung 1: caller keeps
        // per-frame dropping.
        XCTAssertEqual(ladder.evaluate(input(diff: -0.5, wall: 0)), .none)
    }

    func testRung1FlushesDecodedFrames() {
        var ladder = AVSyncLadder()
        XCTAssertEqual(ladder.evaluate(input(diff: -1.2, wall: 0)), .flushDecodedFrames)
    }

    func testRung1RequiresDecodedFrames() {
        var ladder = AVSyncLadder()
        XCTAssertEqual(ladder.evaluate(input(diff: -1.2, decoded: 0, packets: 0, wall: 0)), .none)
    }

    func testCooldownBlocksBackToBackActions() {
        var ladder = AVSyncLadder()
        XCTAssertEqual(ladder.evaluate(input(diff: -1.2, wall: 0)), .flushDecodedFrames)
        XCTAssertEqual(ladder.evaluate(input(diff: -1.6, wall: 0.5)), .none)
        XCTAssertEqual(ladder.evaluate(input(diff: -1.6, wall: 1.1)), .dropPacketsToNextKeyframe)
    }

    func testRung2RequiresPriorFlushOrEmptyScheduler() {
        var ladder = AVSyncLadder()
        // Straight to -1.6 with decoded frames and no prior flush → rung 1
        // first (flush), not rung 2.
        XCTAssertEqual(ladder.evaluate(input(diff: -1.6, wall: 0)), .flushDecodedFrames)
        XCTAssertEqual(ladder.evaluate(input(diff: -1.6, wall: 1.1)), .dropPacketsToNextKeyframe)
    }

    func testDecodeBoundStallGoesStraightToRung2() {
        var ladder = AVSyncLadder()
        // Empty decoded queue + packet backlog = decode-bound; rung 1 has
        // nothing to flush.
        XCTAssertEqual(
            ladder.evaluate(input(diff: -1.6, decoded: 0, packets: 500, wall: 0)),
            .dropPacketsToNextKeyframe
        )
    }

    func testRung2RequiresPacketBacklog() {
        var ladder = AVSyncLadder()
        XCTAssertEqual(ladder.evaluate(input(diff: -1.6, decoded: 0, packets: 0, wall: 0)), .none)
    }

    func testRung3RequiresSustainedCatastrophicDesync() {
        var ladder = AVSyncLadder()
        // First observation arms the sustain timer — and may fire lower
        // rungs meanwhile (flush at -9 s is still correct).
        XCTAssertEqual(ladder.evaluate(input(diff: -9, wall: 0)), .flushDecodedFrames)
        // Sustained past 1 s (and past cooldown) → full reseek.
        XCTAssertEqual(ladder.evaluate(input(diff: -9, wall: 1.2)), .reseekToClock)
    }

    func testRung3ResetsWhenDesyncClears() {
        var ladder = AVSyncLadder()
        XCTAssertEqual(ladder.evaluate(input(diff: -9, wall: 0)), .flushDecodedFrames)
        // Recovers before the sustain window elapses...
        XCTAssertEqual(ladder.evaluate(input(diff: 0, wall: 0.5)), .none)
        // ...so a new catastrophic dip re-arms rather than firing instantly.
        XCTAssertEqual(ladder.evaluate(input(diff: -9, decoded: 0, packets: 0, wall: 2.5)), .none)
        XCTAssertEqual(ladder.evaluate(input(diff: -9, decoded: 0, packets: 0, wall: 4.0)), .reseekToClock)
    }

    func testEpisodeResetRequiresRung1AgainAfterRecovery() {
        var ladder = AVSyncLadder()
        XCTAssertEqual(ladder.evaluate(input(diff: -1.6, wall: 0)), .flushDecodedFrames)
        XCTAssertEqual(ladder.evaluate(input(diff: 0, wall: 1)), .none)
        // New episode: decoded frames present again → rung 1, not rung 2.
        XCTAssertEqual(ladder.evaluate(input(diff: -1.6, wall: 5)), .flushDecodedFrames)
    }
}
