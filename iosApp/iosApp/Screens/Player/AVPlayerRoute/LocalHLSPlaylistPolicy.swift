import Foundation

enum LocalHLSPlaylistPolicy {
    enum PlaylistType: Equatable {
        case liveSliding
        case vod

        var hlsTag: String? {
            switch self {
            case .liveSliding: return nil
            case .vod: return "#EXT-X-PLAYLIST-TYPE:VOD"
            }
        }
    }

    /// When the store retires (deletes) old segment bytes to stay under the
    /// spill budget, the manifest MUST drop those segments too. The manifest
    /// is sliding-live from the first publish, so retiring bytes only advances
    /// `firstMediaSequence`; it does not change playlist type mid-session.
    static let shouldRemoveRetiredSegmentsFromPlaylist = true

    static func shouldEmitStartTag(firstMediaSequence: Int) -> Bool {
        firstMediaSequence <= 0
    }

    static func playlistType(isFinal: Bool) -> PlaylistType {
        isFinal ? .vod : .liveSliding
    }
}
