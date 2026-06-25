import Foundation

enum PlaybackSourcePrefetchPolicy {
    static func initialOffset(
        sourceStartTimeSeconds: Double,
        sourceBitrateBps: Double?
    ) -> Int64 {
        guard sourceStartTimeSeconds.isFinite,
              sourceStartTimeSeconds > 0,
              let sourceBitrateBps,
              sourceBitrateBps.isFinite,
              sourceBitrateBps > 0 else {
            return 0
        }

        let offset = (sourceStartTimeSeconds * sourceBitrateBps / 8).rounded(.down)
        guard offset.isFinite, offset > 0 else { return 0 }

        return Int64(min(offset, Double(Int64.max - 1)))
    }

    static func shouldRetargetPrefetch(
        activeStart: Int64,
        requestedStart: Int64,
        chunkBytes: Int
    ) -> Bool {
        guard chunkBytes > 0 else { return activeStart != requestedStart }

        let active = max(0, activeStart)
        let requested = max(0, requestedStart)
        let distance = active >= requested ? active - requested : requested - active

        return distance > Int64(chunkBytes * 2)
    }
}
