//
//  SubtitleSession.swift
//  Continuum (iOS + tvOS)
//
//  Session-level coordinator for subtitle sources. Owns the mapping from
//  `PlayerTrack` selection (both embedded FFmpeg streams and server-
//  provided sidecar URLs) to the libass-backed `SubtitleRenderer`. Also
//  owns the sidecar fetch tasks and the in-session content cache.
//
//  Lives for the lifetime of one playback session. Held by `PlayerCore`
//  via a strong reference; torn down in `PlayerCore.dispose`.
//

import Foundation
import OSLog

/// Descriptor for a server-provided sidecar subtitle track. Copied
/// verbatim from `Networking/Models.swift` / `SubtitleUrl` into a
/// local struct so the subtitle layer doesn't pull in the full
/// playback-session model graph.
struct SidecarSubtitleDescriptor: Hashable {
    let index: Int
    let language: String?
    let codec: String?
    let label: String?
    let source: String?
    let forced: Bool?
    /// Absolute URL (server URL already resolved against the relative
    /// path that came back from `/playback/start`).
    let url: URL
}

final class SubtitleSession {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.continuum.app",
        category: "SubtitleSession"
    )

    private let renderer: SubtitleRenderer
    private let fetcher: SidecarSubtitleFetcher

    /// Sidecar descriptors keyed by their server-assigned URL index.
    /// Populated once on playback start; read on demand when the user
    /// selects a sidecar track.
    private var sidecarDescriptors: [Int: SidecarSubtitleDescriptor] = [:]
    var hasRegisteredSidecars: Bool {
        !sidecarDescriptors.isEmpty
    }

    /// Caller-supplied way to read the current playback position in
    /// seconds. Used for subtitle diagnostics and future seek-aware
    /// fetch paths.
    var currentPositionSecondsProvider: (() -> Double)?

    /// In-flight or completed sidecar content. Prevents re-fetching a
    /// track the user toggles on/off repeatedly. Cleared on teardown.
    private var sidecarCache: [Int: String] = [:]

    /// Active per-slot fetch Task so switching tracks cancels the
    /// previous fetch cleanly.
    private var fetchTasks: [SubtitleSlot: Task<Void, Never>] = [:]

    /// Current user styling parameters. Snapshot updated by PlayerCore
    /// when `applySubtitleStyling` is called.
    private var stylingParams: SubtitleStylingOverride.Parameters = .default

    /// Fires on main when a slot's loading status changes.
    var onStatusChange: ((SubtitleSlot, SubtitleLoadStatus) -> Void)?

    /// Fires on main when sidecar tracks have been registered and the
    /// VM should extend `subtitleTracks` with the synthesised entries.
    var onSidecarTracksRegistered: (([SidecarSubtitleDescriptor]) -> Void)?

    init(
        renderer: SubtitleRenderer = SubtitleRenderer(),
        fetcher: SidecarSubtitleFetcher = SidecarSubtitleFetcher()
    ) {
        self.renderer = renderer
        self.fetcher = fetcher
    }

    /// Handle on the underlying renderer — exposed so PlayerCore can
    /// drive display-link ticks and overlay views can read the current
    /// frame size bookkeeping.
    var underlyingRenderer: SubtitleRenderer { renderer }

    // MARK: - Configuration

    func applyStyling(_ params: SubtitleStylingOverride.Parameters) {
        stylingParams = params
        renderer.applySettings(params)
    }

    var currentParams: SubtitleStylingOverride.Parameters { stylingParams }

    // MARK: - Sidecar track registry

    /// Register sidecar tracks returned by the playback-start session.
    /// Fires `onSidecarTracksRegistered` on main so the VM can append
    /// synthesised `PlayerTrack` entries to `subtitleTracks`.
    func registerSidecarTracks(_ descriptors: [SidecarSubtitleDescriptor]) {
        sidecarDescriptors.removeAll()
        for d in descriptors {
            sidecarDescriptors[d.index] = d
        }
        Self.logger.info(
            "[CMP-SUB] session registered sidecar descriptors=\(descriptors.count, privacy: .public) indices=\(descriptors.map { String($0.index) }.joined(separator: ","), privacy: .public)"
        )
        let snapshot = descriptors
        DispatchQueue.main.async { [weak self] in
            self?.onSidecarTracksRegistered?(snapshot)
        }
    }

    // MARK: - Track switching

    /// Open an embedded FFmpeg subtitle track in the given slot.
    /// `extradata`/`extradataSize` are from the `AVCodecContext` —
    /// they carry the ASS `[Script Info]` + `[V4+ Styles]` block
    /// (either authored, for native ASS, or FFmpeg-synthesized for
    /// SRT/WebVTT/MOVTEXT codecs).
    ///
    /// Called from `PlayerCore` on its control queue.
    func openEmbedded(
        slot: SubtitleSlot,
        isNativeASS: Bool,
        extradata: UnsafePointer<UInt8>?,
        extradataSize: Int
    ) {
        cancelFetchTask(for: slot)
        if isNativeASS {
            renderer.createTrack(
                slot: slot,
                isNativeASS: true,
                extradata: extradata,
                extradataSize: extradataSize
            )
        } else {
            // FFmpeg synthesizes ASS headers for embedded SRT/WebVTT/MOVTEXT
            // with codec-specific PlayRes/font defaults. Feed the same
            // controlled header used by external text sidecars so appearance
            // does not change when switching subtitle source types.
            let header = SubtitleStylingOverride.syntheticHeader(
                params: stylingParams,
                slot: slot
            )
            Data(header.utf8).withUnsafeBytes { raw in
                renderer.createTrack(
                    slot: slot,
                    isNativeASS: false,
                    extradata: raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    extradataSize: raw.count
                )
            }
        }
        publishStatus(slot: slot, .ready)
    }

    /// Open a sidecar subtitle track (server URL) in the given slot.
    /// Starts an async fetch; when the content arrives it's fed to the
    /// renderer (converted from VTT/SRT to ASS if needed).
    ///
    /// All controlled sidecar text formats are installed into libass. ASS /
    /// SSA are passed through as authored documents; SRT, VTT, and MOV_TEXT
    /// are converted into a generated ASS document first.
    func openSidecar(urlIndex: Int, slot: SubtitleSlot) {
        guard let descriptor = sidecarDescriptors[urlIndex] else {
            Self.logger.warning("openSidecar: no descriptor for index \(urlIndex)")
            publishStatus(slot: slot, .error("Subtitle track not found"))
            return
        }

        cancelFetchTask(for: slot)
        publishStatus(slot: slot, .fetching)

        // The server/CDN subtitle endpoint can buffer text responses long
        // enough that URLSession.AsyncBytes never yields a first cue before
        // playback has moved on. Use the buffered path for now so SRT/VTT
        // sidecars reliably become renderable; true streaming can be restored
        // once the endpoint is proven to flush cue lines progressively.
        Self.logger.info(
            "[CMP-SUB] open sidecar index=\(urlIndex, privacy: .public) slot=\(slot.rawValue, privacy: .public) codec=\(descriptor.codec ?? "nil", privacy: .public) streaming=false"
        )

        openSidecarBuffered(urlIndex: urlIndex, descriptor: descriptor, slot: slot)
    }

    private func openSidecarBuffered(
        urlIndex: Int,
        descriptor: SidecarSubtitleDescriptor,
        slot: SubtitleSlot
    ) {
        // Fast path: cached.
        if let cached = sidecarCache[urlIndex] {
            installSidecarContent(
                content: cached,
                codecHint: descriptor.codec,
                url: descriptor.url,
                slot: slot
            )
            return
        }

        let localFetcher = fetcher
        let task = Task { [weak self] in
            do {
                let result = try await localFetcher.fetch(
                    url: descriptor.url,
                    preferredFormatHint: Self.codecToFormat(descriptor.codec)
                )
                guard let self else { return }
                if Task.isCancelled { return }

                Self.logger.info(
                    "[CMP-SUB] fetched sidecar index=\(urlIndex, privacy: .public) slot=\(slot.rawValue, privacy: .public) format=\(String(describing: result.format), privacy: .public) chars=\(result.content.count, privacy: .public)"
                )
                self.sidecarCache[urlIndex] = result.content
                self.installSidecarContent(
                    content: result.content,
                    codecHint: descriptor.codec,
                    url: descriptor.url,
                    slot: slot,
                    knownFormat: result.format
                )
            } catch {
                Self.logger.warning("sidecar fetch failed: \(String(describing: error), privacy: .public)")
                self?.publishStatus(slot: slot, .error("Couldn't load subtitle"))
            }
        }
        fetchTasks[slot] = task
    }

    /// Close the given slot. Drops the libass track and cancels any
    /// in-flight fetch.
    func closeSlot(_ slot: SubtitleSlot) {
        cancelFetchTask(for: slot)
        renderer.dropTrack(slot: slot)
        publishStatus(slot: slot, .idle)
    }

    /// Called on seek so libass clears cached events past the new
    /// position. Does not affect fetch state.
    func flushOnSeek() {
        renderer.flushTrack(slot: .primary)
        renderer.flushTrack(slot: .secondary)
    }

    // MARK: - Embedded event feed

    /// Called by `PlayerCore.decodeSubtitlePacket` for each decoded
    /// packet. `eventText` is the raw `rect.ass` string from FFmpeg
    /// (the Dialogue event content, not the whole `Dialogue:` line).
    func feedEmbedded(
        slot: SubtitleSlot,
        eventText: String,
        startMs: Int64,
        durationMs: Int64
    ) {
        renderer.feedChunk(
            slot: slot,
            eventText: eventText,
            startMs: startMs,
            durationMs: durationMs
        )
    }

    /// Register an embedded font from an FFmpeg `AVMEDIA_TYPE_ATTACHMENT`
    /// stream. Called on file open.
    func registerEmbeddedFont(name: String, data: Data) {
        renderer.addEmbeddedFont(name: name, data: data)
    }

    // MARK: - Lifecycle

    /// Stop all fetches, drop all tracks. Called by `PlayerCore.dispose`.
    func teardown() {
        for task in fetchTasks.values { task.cancel() }
        fetchTasks.removeAll()
        sidecarCache.removeAll()
        sidecarDescriptors.removeAll()
        renderer.dropAllTracks()
    }

    // MARK: - Internals

    private func cancelFetchTask(for slot: SubtitleSlot) {
        fetchTasks[slot]?.cancel()
        fetchTasks[slot] = nil
    }

    private func publishStatus(slot: SubtitleSlot, _ status: SubtitleLoadStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChange?(slot, status)
        }
    }

    private func installSidecarContent(
        content: String,
        codecHint: String?,
        url: URL,
        slot: SubtitleSlot,
        knownFormat: SubtitleFormat? = nil
    ) {
        let format = knownFormat ?? Self.codecToFormat(codecHint) ?? .vtt
        let isNativeASS = (format == .ass)

        let assDocument: String
        switch format {
        case .ass:
            assDocument = content
        case .vtt, .srt:
            assDocument = VTTToASSConverter.convert(
                vtt: content,
                header: SubtitleStylingOverride.syntheticHeader(
                    params: stylingParams,
                    slot: slot
                )
            )
        }

        renderer.installFullASS(
            slot: slot,
            assDocument: assDocument,
            isNativeASS: isNativeASS
        )
        let stats = Self.dialogueStats(in: assDocument)
        let nowSeconds = currentPositionSecondsProvider?() ?? -1
        Self.logger.info(
            "[CMP-SUB] installed sidecar slot=\(slot.rawValue, privacy: .public) format=\(String(describing: format), privacy: .public) nativeASS=\(isNativeASS, privacy: .public) assChars=\(assDocument.count, privacy: .public) dialogueCount=\(stats.count, privacy: .public) first=\(stats.first ?? "nil", privacy: .public) last=\(stats.last ?? "nil", privacy: .public) now=\(nowSeconds, privacy: .public)"
        )
        publishStatus(slot: slot, .ready)
    }

    private static func dialogueStats(in assDocument: String) -> (count: Int, first: String?, last: String?) {
        var count = 0
        var first: String?
        var last: String?
        assDocument.enumerateLines { line, _ in
            guard line.hasPrefix("Dialogue:") else { return }
            count += 1
            let parts = line.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { return }
            let range = "\(parts[1])-\(parts[2])"
            if first == nil { first = range }
            last = range
        }
        return (count, first, last)
    }

    /// Map a server-supplied codec hint (e.g. `"ass"`, `"subrip"`,
    /// `"webvtt"`) to the format the sidecar response is likely to be.
    /// Used as a fallback when the HTTP response doesn't carry a useful
    /// Content-Type, and as an initial expectation for the fetcher.
    static func codecToFormat(_ codec: String?) -> SubtitleFormat? {
        guard let c = codec?.lowercased() else { return nil }
        switch c {
        case "ass", "ssa":            return .ass
        case "subrip", "srt":         return .srt
        case "webvtt", "vtt", "mov_text", "movtext":
            return .vtt
        default:
            return nil
        }
    }
}
