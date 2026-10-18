import CoreGraphics
import Foundation
import ImageIO
import Nuke

/// Seek-bar previews the server published for one file: sprite sheets of
/// thumbnails, one thumbnail per interval of source time. Unlike stills cut
/// from the player's cache, they cover the whole file before any of it has
/// been buffered.
struct ServerTrickplay: Equatable, Sendable {
    let fileId: Int
    /// Source time each thumbnail covers, in seconds.
    let interval: Double
    let thumbnailWidth: Int
    let thumbnailHeight: Int
    let columns: Int
    let rows: Int
    let count: Int
    /// One URL per sheet, in order. Each carries its own authorization.
    let sheetURLs: [URL]
    let expiresAt: Date

    struct Tile: Equatable {
        let sheet: Int
        /// The thumbnail's rectangle within its sheet, at full size.
        let rect: CGRect
    }

    enum InvalidManifest: Error {
        case geometry
        case sheets
    }

    /// The thumbnail shown for a source time, clamped to the last one.
    func tile(atSourceTime seconds: Double) -> Tile? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let position = seconds / interval
        let index = position >= Double(count - 1) ? count - 1 : Int(position)
        let perSheet = columns * rows
        let cell = index % perSheet
        return Tile(
            sheet: index / perSheet,
            rect: CGRect(
                x: (cell % columns) * thumbnailWidth,
                y: (cell / columns) * thumbnailHeight,
                width: thumbnailWidth,
                height: thumbnailHeight
            )
        )
    }

    /// Whether another manifest lays out the same thumbnails, so its sheet
    /// URLs can replace these ones.
    func hasSameLayout(as other: ServerTrickplay) -> Bool {
        fileId == other.fileId && interval == other.interval
            && thumbnailWidth == other.thumbnailWidth && thumbnailHeight == other.thumbnailHeight
            && columns == other.columns && rows == other.rows && count == other.count
            && sheetURLs.count == other.sheetURLs.count
    }
}

/// Fetches one manifest's sheets and cuts thumbnails from them. Sheets load
/// through the app's artwork pipeline, so they share its disk cache (keyed
/// without the URL signature) and its local route. They are kept here as
/// JPEG data, a few hundred kilobytes each, and only the most recent one is
/// kept decoded, so a long file does not hold every sheet in memory as a
/// bitmap.
actor ServerTrickplaySheets {
    /// How long a scrub waits for a sheet that is still downloading before
    /// it gives up on this target; the download carries on for later ones.
    private static let sheetWait: Duration = .seconds(1)
    /// Sheet URLs are renewed this long before the manifest says they expire.
    private static let renewalMargin: TimeInterval = 30
    /// A sheet that failed to download, and the manifest after a renewal, are
    /// not requested again for this long, so a scrub over a failing sheet
    /// does not send a request for every target.
    private static let retryBackoff: TimeInterval = 30

    private var trickplay: ServerTrickplay
    private let renew: @Sendable () async -> ServerTrickplay?
    private var data: [Int: Data] = [:]
    private var fetches: [Int: Task<Data?, Never>] = [:]
    private var failedAt: [Int: Date] = [:]
    private var renewal: Task<Void, Never>?
    private var renewedAt: Date?
    private var decoded: (sheet: Int, image: CGImage)?
    /// Bumped when a renewed manifest lays out different thumbnails; work
    /// started for the old layout is then dropped.
    private var layout: UInt64 = 0
    private var closed = false

    /// `renew` fetches the manifest again, for fresh sheet URLs once these
    /// expire.
    init(_ trickplay: ServerTrickplay, renew: @escaping @Sendable () async -> ServerTrickplay?) {
        self.trickplay = trickplay
        self.renew = renew
    }

    /// Cancels every download, so closing the player does not wait on them.
    func shutdown() {
        closed = true
        for fetch in fetches.values { fetch.cancel() }
        fetches = [:]
        renewal?.cancel()
    }

    /// Fetches every sheet in order, so a scrub anywhere in the file finds
    /// its thumbnail without a round trip. A whole film is a handful of
    /// sheets; one that fails is fetched again when a scrub needs it. A
    /// renewal that lays the thumbnails out again restarts it on the new
    /// sheets.
    func prefetch() async {
        var sheet = 0
        var layout = layout
        while sheet < trickplay.sheetURLs.count {
            if Task.isCancelled || closed { return }
            if layout != self.layout {
                layout = self.layout
                sheet = 0
            }
            if data[sheet] == nil, let fetch = fetch(sheet) {
                _ = await fetch.value
            }
            if layout == self.layout { sheet += 1 }
        }
    }

    /// The thumbnail for a source time, or nil when its sheet is not
    /// available. With `waitingForDownload`, a sheet still downloading is
    /// awaited for a short while; without it, the download is only started.
    func thumbnail(atSourceTime seconds: Double, waitingForDownload: Bool = true) async -> CGImage? {
        let layout = layout
        guard let tile = trickplay.tile(atSourceTime: seconds),
              let image = await sheetImage(tile.sheet, waitingForDownload: waitingForDownload),
              layout == self.layout else { return nil }
        // A sheet is laid out at the manifest's size; scale the cut if the
        // image is not.
        let scale = CGFloat(image.width) / CGFloat(trickplay.columns * trickplay.thumbnailWidth)
        let rect = CGRect(
            x: tile.rect.minX * scale, y: tile.rect.minY * scale,
            width: tile.rect.width * scale, height: tile.rect.height * scale
        ).integral
        return image.cropping(to: rect)
    }

    private func sheetImage(_ sheet: Int, waitingForDownload: Bool) async -> CGImage? {
        if let decoded, decoded.sheet == sheet { return decoded.image }
        let layout = layout
        guard let bytes = await sheetData(sheet, waitingForDownload: waitingForDownload),
              layout == self.layout,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else { return nil }
        decoded = (sheet, image)
        return image
    }

    private func sheetData(_ sheet: Int, waitingForDownload: Bool) async -> Data? {
        guard !closed, trickplay.sheetURLs.indices.contains(sheet) else { return nil }
        if let bytes = data[sheet] { return bytes }
        guard let fetch = fetch(sheet), waitingForDownload else { return nil }
        return await Self.value(of: fetch, within: Self.sheetWait)
    }

    /// Reports whether the sheet for a source time is held, waiting first
    /// for a download in flight however long it takes. A scrub that gave up
    /// on the sheet uses this to ask again once it arrives. Without a sheet
    /// held or downloading, the answer is false.
    func awaitSheet(atSourceTime seconds: Double) async -> Bool {
        let layout = layout
        guard !closed, let tile = trickplay.tile(atSourceTime: seconds) else { return false }
        if data[tile.sheet] == nil, let fetch = fetches[tile.sheet] {
            _ = await fetch.value
        }
        return !closed && layout == self.layout && data[tile.sheet] != nil
    }

    /// A download's result, or nil once `limit` passes. Returning at the
    /// deadline does not wait for or cancel the download: it is an
    /// unstructured task and keeps the sheet for the next scrub.
    private static func value(of fetch: Task<Data?, Never>, within limit: Duration) async -> Data? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { once.resume(with: await fetch.value) }
            Task {
                try? await Task.sleep(for: limit)
                once.resume(with: nil)
            }
        }
    }

    /// The download in flight for a sheet, starting one unless the sheet
    /// failed within the backoff.
    private func fetch(_ sheet: Int) -> Task<Data?, Never>? {
        if let fetch = fetches[sheet] { return fetch }
        if let failed = failedAt[sheet], -failed.timeIntervalSinceNow < Self.retryBackoff { return nil }
        let layout = layout
        let fetch = Task<Data?, Never> {
            let bytes = await download(sheet)
            // A layout change replaced `fetches` and the held sheets.
            guard layout == self.layout else { return nil }
            fetches[sheet] = nil
            if closed || Task.isCancelled { return bytes }
            if let bytes {
                data[sheet] = bytes
                failedAt[sheet] = nil
            } else {
                failedAt[sheet] = Date()
            }
            return bytes
        }
        fetches[sheet] = fetch
        return fetch
    }

    /// Downloads a sheet, renewing the manifest first when its URLs are
    /// about to expire and the sheet is not cached, and once more when the
    /// server refuses them.
    private func download(_ sheet: Int) async -> Data? {
        if trickplay.expiresAt.timeIntervalSinceNow < Self.renewalMargin,
           trickplay.sheetURLs.indices.contains(sheet),
           !ImagePipeline.shared.cache.containsData(for: ImageRequest(artwork: trickplay.sheetURLs[sheet])) {
            await renewManifest()
        }
        var result = await get(sheet)
        if result.refused {
            await renewManifest()
            result = await get(sheet)
        }
        return result.bytes
    }

    private func get(_ sheet: Int) async -> (bytes: Data?, refused: Bool) {
        guard !closed, !Task.isCancelled, trickplay.sheetURLs.indices.contains(sheet) else {
            return (nil, false)
        }
        do {
            return (try await ImagePipeline.shared.data(for: ImageRequest(artwork: trickplay.sheetURLs[sheet])).0, false)
        } catch ImagePipeline.Error.dataLoadingFailed(let error) {
            guard case let DataLoader.Error.statusCodeUnacceptable(status) = error else { return (nil, false) }
            return (nil, status == 401 || status == 403)
        } catch {
            return (nil, false)
        }
    }

    /// Installs a fresh manifest's sheet URLs. Sheets already downloaded are
    /// kept unless the thumbnails were laid out again. Concurrent callers
    /// share one request, which installs before any of them resumes; a
    /// renewal is not repeated within the backoff.
    private func renewManifest() async {
        guard !closed else { return }
        if let renewal {
            await renewal.value
            return
        }
        if let renewedAt, -renewedAt.timeIntervalSinceNow < Self.retryBackoff { return }
        renewedAt = Date()
        let task = Task { [renew] in
            let renewed = await renew()
            install(renewed)
        }
        renewal = task
        await task.value
    }

    private func install(_ renewed: ServerTrickplay?) {
        renewal = nil
        guard !closed, let renewed, renewed.fileId == trickplay.fileId else { return }
        let sameLayout = renewed.hasSameLayout(as: trickplay)
        trickplay = renewed
        guard !sameLayout else { return }
        // The file's previews were made again: the sheets held cut the old
        // thumbnails.
        layout &+= 1
        for fetch in fetches.values { fetch.cancel() }
        fetches = [:]
        data = [:]
        failedAt = [:]
        decoded = nil
    }
}

/// Resumes a continuation with the first result offered and ignores the rest.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?

    init(_ continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
    }

    func resume(with value: Data?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
