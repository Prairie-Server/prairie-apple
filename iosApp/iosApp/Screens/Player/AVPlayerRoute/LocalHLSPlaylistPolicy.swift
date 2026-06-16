import Foundation

enum LocalHLSPlaylistPolicy {
    static let shouldRemoveRetiredSegmentsFromPlaylist = false

    static func shouldEmitStartTag(firstMediaSequence: Int) -> Bool {
        firstMediaSequence <= 0
    }
}
