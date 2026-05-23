import Foundation

extension PlayerCore {
    struct LoadRequest {
        let url: URL
        let headers: [String: String]
        let startTime: Double
    }

    struct ChapterInfo: Equatable, Identifiable {
        let index: Int
        let title: String?
        let time: Double
        var id: Int { index }
    }

    /// Reasons PlayerCore rejects a stream. The VM decides what to do with
    /// the rejection (e.g. route to an AVPlayer-backed fallback) — the
    /// core itself stays agnostic about fallbacks.
    enum StreamRejection {
        /// Dolby Vision Profile 5: `buildVideoFormatDescription` detected
        /// `AV_PKT_DATA_DOVI_CONF` with profile 5.
        case dolbyVisionProfile5
        /// `VTDecompressionSessionCreate` returned unimpErr on HEVC+PQ.
        /// Treated as a likely unsignalled DV stream (DOVI conf not surfaced
        /// by libavformat for this container).
        case videoToolboxUnsupportedHEVCPQ
        /// `VTDecompressionSessionCreate` returned unimpErr on iPhone HEVC
        /// HDR (for example HLG) after relaxed retries. Route the original
        /// source URL through the AVPlayer backend instead of failing hard.
        case videoToolboxUnsupportedHEVCHDR
        /// VideoToolbox accepted the H.264 session but then rejected the
        /// compressed samples as bad data. This is terminal for H.264 direct
        /// playback; do not mask it with software fallback.
        case videoToolboxBadDataH264
    }
}
