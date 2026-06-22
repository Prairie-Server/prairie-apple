import XCTest
import Foundation
@testable import Silo

final class LocalHLSPlaylistPolicyTests: XCTestCase {
    func testStartTagIsStartupOnly() {
        XCTAssertTrue(
            LocalHLSPlaylistPolicy.shouldEmitStartTag(firstMediaSequence: 0),
            "initial live playlist should keep EXT-X-START for the first AVPlayer attach"
        )
        XCTAssertFalse(
            LocalHLSPlaylistPolicy.shouldEmitStartTag(firstMediaSequence: 1),
            "sliding live playlist should not keep EXT-X-START anchored at the moving head"
        )
    }

    func testSpillRetirementDropsSegmentsFromPlaylist() {
        XCTAssertTrue(
            LocalHLSPlaylistPolicy.shouldRemoveRetiredSegmentsFromPlaylist,
            "retiring old segment bytes from the store must also drop them from the manifest, "
                + "otherwise AVPlayer fetches a retired (.gone) URI and fails with HTTP 410 on a backward seek"
        )
    }

    func testNonFinalPlaylistIsSlidingLiveFromFirstPublish() {
        XCTAssertEqual(LocalHLSPlaylistPolicy.playlistType(isFinal: false), .liveSliding)
        XCTAssertNil(LocalHLSPlaylistPolicy.playlistType(isFinal: false).hlsTag)
    }

    func testFinalPlaylistIsVOD() {
        XCTAssertEqual(LocalHLSPlaylistPolicy.playlistType(isFinal: true), .vod)
        XCTAssertEqual(LocalHLSPlaylistPolicy.playlistType(isFinal: true).hlsTag, "#EXT-X-PLAYLIST-TYPE:VOD")
    }
}
