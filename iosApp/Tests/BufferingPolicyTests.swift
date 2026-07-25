import XCTest
@testable import Prairie

final class BufferingPolicyTests: XCTestCase {
    private func sample(
        video: Double? = nil,
        audio: Double? = nil,
        hungry: Bool? = true,
        playing: Bool = true,
        eof: Bool = false,
        postSeek: Bool = false
    ) -> BufferingPolicy.Sample {
        BufferingPolicy.Sample(
            videoBufferedSeconds: video,
            audioBufferedSeconds: audio,
            audioRendererHungry: hungry,
            isPlaying: playing,
            reachedInputEOF: eof,
            withinPostSeekWindow: postSeek
        )
    }

    func testEntersOnStarvationAndLeavesAtCushion() {
        var policy = BufferingPolicy()
        XCTAssertFalse(policy.evaluate(sample(video: 5, audio: 5)))
        XCTAssertTrue(policy.evaluate(sample(video: 0.1, audio: 0.05)))
        // Between the thresholds: state must hold (hysteresis, no flap).
        XCTAssertTrue(policy.evaluate(sample(video: 1.0, audio: 1.0)))
        XCTAssertTrue(policy.evaluate(sample(video: 2.9, audio: 2.9)))
        XCTAssertFalse(policy.evaluate(sample(video: 3.2, audio: 3.2)))
        // Dropping back into the band must NOT re-enter buffering.
        XCTAssertFalse(policy.evaluate(sample(video: 1.0, audio: 1.0)))
    }

    func testMinAcrossTracksBinds() {
        var policy = BufferingPolicy()
        // Video plentiful, audio starved → buffering.
        XCTAssertTrue(policy.evaluate(sample(video: 20, audio: 0.05)))
        // Audio recovers past leave but video is now the binding track.
        XCTAssertTrue(policy.evaluate(sample(video: 0.5, audio: 10)))
        XCTAssertFalse(policy.evaluate(sample(video: 4, audio: 10)))
    }

    func testEOFSuppressesBuffering() {
        var policy = BufferingPolicy()
        XCTAssertFalse(policy.evaluate(sample(video: 0.05, audio: 0.05, eof: true)))
        // Already-buffering state clears when EOF lands (drain-out).
        XCTAssertTrue(policy.evaluate(sample(video: 0.05, audio: 0.05)))
        XCTAssertFalse(policy.evaluate(sample(video: 0.05, audio: 0.05, eof: true)))
    }

    func testPostSeekWindowHalvesLeaveThreshold() {
        var policy = BufferingPolicy()
        XCTAssertTrue(policy.evaluate(sample(video: 0.1, audio: 0.1, postSeek: true)))
        // 1.6 s ≥ post-seek leave (1.5) but < steady-state leave (3.0).
        XCTAssertFalse(policy.evaluate(sample(video: 1.6, audio: 1.6, postSeek: true)))

        var steady = BufferingPolicy()
        XCTAssertTrue(steady.evaluate(sample(video: 0.1, audio: 0.1)))
        XCTAssertTrue(steady.evaluate(sample(video: 1.6, audio: 1.6)))
    }

    func testRendererHungryGatesEntryWhenAudioExists() {
        var policy = BufferingPolicy()
        // Starved queue but renderer isn't asking → not buffering (paused
        // renderer, at-capacity idle, etc.).
        XCTAssertFalse(policy.evaluate(sample(video: 0.05, audio: 0.05, hungry: false)))
        XCTAssertTrue(policy.evaluate(sample(video: 0.05, audio: 0.05, hungry: true)))
    }

    func testVideoOnlyFilesCanBuffer() {
        var policy = BufferingPolicy()
        // No audio stream: hungry is nil, starvation alone decides.
        XCTAssertTrue(policy.evaluate(sample(video: 0.05, audio: nil, hungry: nil)))
        XCTAssertFalse(policy.evaluate(sample(video: 5, audio: nil, hungry: nil)))
    }

    func testNoTracksNeverBuffers() {
        var policy = BufferingPolicy()
        XCTAssertFalse(policy.evaluate(sample(video: nil, audio: nil, hungry: nil)))
    }

    func testNotPlayingClearsState() {
        var policy = BufferingPolicy()
        XCTAssertTrue(policy.evaluate(sample(video: 0.05, audio: 0.05)))
        XCTAssertFalse(policy.evaluate(sample(video: 0.05, audio: 0.05, playing: false)))
    }

    func testProgressInputsExposed() {
        var policy = BufferingPolicy()
        policy.evaluate(sample(video: 1.2, audio: 2.4))
        XCTAssertEqual(policy.lastMinBufferedSeconds, 1.2)
        XCTAssertEqual(policy.activeLeaveThresholdSeconds, 3.0)
        policy.evaluate(sample(video: 1.2, audio: 2.4, postSeek: true))
        XCTAssertEqual(policy.activeLeaveThresholdSeconds, 1.5)
    }
}
