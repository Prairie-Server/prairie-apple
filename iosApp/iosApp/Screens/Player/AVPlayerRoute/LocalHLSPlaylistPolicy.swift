import Foundation

enum LocalHLSPlaylistPolicy {
    /// When the store retires (deletes) old segment bytes to stay under the
    /// spill budget, the manifest MUST drop those segments too. Leaving them
    /// listed while the store answers `.gone` makes AVPlayer fetch a retired
    /// URI and fail with HTTP 410 (-12642) on any backward seek past the
    /// retention window. Removing them turns the manifest into a sliding live
    /// playlist (`firstMediaSequence` advances, the EVENT tag drops), so
    /// `itemHasSeekableMedia` reports the retired band as unseekable and a deep
    /// backward seek re-anchors the loopback (regenerates from the target)
    /// instead of 410ing.
    static let shouldRemoveRetiredSegmentsFromPlaylist = true

    static func shouldEmitStartTag(firstMediaSequence: Int) -> Bool {
        firstMediaSequence <= 0
    }
}
