import Foundation

@main
struct LocalHLSPlaylistPolicyTests {
    static func main() {
        testStartTagIsStartupOnly()
        testSpillRetirementKeepsPlaylistAppendOnly()
        print("LocalHLSPlaylistPolicyTests: all passed")
    }

    private static func testStartTagIsStartupOnly() {
        precondition(
            LocalHLSPlaylistPolicy.shouldEmitStartTag(firstMediaSequence: 0),
            "initial EVENT playlist should keep EXT-X-START for the first AVPlayer attach"
        )
        precondition(
            !LocalHLSPlaylistPolicy.shouldEmitStartTag(firstMediaSequence: 1),
            "sliding live playlist should not keep EXT-X-START anchored at the moving head"
        )
    }

    private static func testSpillRetirementKeepsPlaylistAppendOnly() {
        precondition(
            !LocalHLSPlaylistPolicy.shouldRemoveRetiredSegmentsFromPlaylist,
            "retiring old segment bytes from the store must not turn the manifest into a sliding live playlist"
        )
    }
}
