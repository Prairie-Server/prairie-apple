import Foundation

// Prairie stats-for-nerds detail that Aether cannot supply: the server's
// playback plan, the stream path handed to the player, and a short rolling
// log of player events. Parity with prairie-smarttv #116 and the web overlay.
// Everything here is pure Foundation so the formatting is unit-testable.

/// Bounded, oldest-first log of recent player events and errors.
///
/// Recorded whether or not diagnostics upload is enabled, so a failure can be
/// read on the device itself. Messages pass through `MediaLogRedactor`, which
/// strips URLs, credentials and media filenames before anything is stored.
struct PlaybackEventLog: Equatable {
    enum Kind: String, Equatable {
        case info
        case warning
        case error
    }

    struct Entry: Equatable {
        var at: Date
        let kind: Kind
        let message: String
        /// How many identical consecutive events this entry stands for.
        var repeatCount: Int = 1
    }

    static let defaultCapacity = 8
    static let maxMessageLength = 160

    let capacity: Int
    private(set) var entries: [Entry] = []

    init(capacity: Int = PlaybackEventLog.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// Appends an event, dropping the oldest once `capacity` is reached. An
    /// event identical to the newest one (same kind and message) bumps that
    /// entry's count and timestamp instead, so a flapping state can't flush
    /// the error that caused it.
    mutating func record(_ message: String, kind: Kind = .info, at date: Date = Date()) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sanitized = MediaLogRedactor.sanitize(trimmed, maxLength: Self.maxMessageLength)
        if var last = entries.last, last.kind == kind, last.message == sanitized {
            last.at = date
            last.repeatCount += 1
            entries[entries.count - 1] = last
            return
        }
        entries.append(Entry(at: date, kind: kind, message: sanitized))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    var newestFirst: [Entry] { entries.reversed() }
}

extension PlaybackEventLog.Entry {
    /// `12:04:31` in the device's time zone; seconds matter for correlating
    /// with server logs.
    func timeLabel(timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: at)
        return String(
            format: "%02d:%02d:%02d",
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }

    /// Message with a severity prefix for warnings and errors and a `×N`
    /// suffix for collapsed repeats.
    var displayMessage: String {
        var text: String
        switch kind {
        case .info: text = message
        case .warning: text = "Warning: \(message)"
        case .error: text = "Error: \(message)"
        }
        if repeatCount > 1 {
            text += " ×\(repeatCount)"
        }
        return text
    }
}

/// One-line description of the negotiated protocol-v3 plan.
struct PlaybackPlanSummary: Equatable {
    /// Raw server delivery (`original_http`, `server_remux_hls`, …).
    let delivery: String
    let container: String?
    let videoCodec: String?
    let width: Int?
    let height: Int?
    let dynamicRange: String?
    let audioCodec: String?
    let audioChannels: Int?
    let bitrateKbps: Int?
    /// Planner's `decision_reason`.
    let reason: String?

    init(
        delivery: String,
        container: String? = nil,
        videoCodec: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        dynamicRange: String? = nil,
        audioCodec: String? = nil,
        audioChannels: Int? = nil,
        bitrateKbps: Int? = nil,
        reason: String? = nil
    ) {
        self.delivery = delivery
        self.container = container
        self.videoCodec = videoCodec
        self.width = width
        self.height = height
        self.dynamicRange = dynamicRange
        self.audioCodec = audioCodec
        self.audioChannels = audioChannels
        self.bitrateKbps = bitrateKbps
        self.reason = reason
    }

    /// The effective recipe describes what the player receives; fall back to
    /// the source descriptor for fields a direct-play plan leaves empty.
    init(plan: PlaybackV3Plan) {
        let recipe = plan.effectiveRecipe
        let source = plan.source
        self.init(
            delivery: plan.delivery,
            container: plan.stream.container ?? source.container,
            videoCodec: recipe.videoCodec ?? source.videoCodec,
            width: recipe.width ?? source.width,
            height: recipe.height ?? source.height,
            dynamicRange: recipe.dynamicRange ?? source.dynamicRange,
            audioCodec: recipe.audioCodec ?? source.audioCodec,
            audioChannels: recipe.audioChannels ?? source.audioChannels,
            bitrateKbps: recipe.bitrateKbps ?? source.bitrateKbps,
            reason: plan.decisionReason
        )
    }

    /// Direct play, Remux or Transcode, with the transport when it matters.
    var method: String {
        Self.method(forDelivery: delivery)
    }

    static func method(forDelivery delivery: String) -> String {
        switch delivery.lowercased() {
        case "original_http": return "Direct play"
        case "server_remux_progressive": return "Remux (progressive)"
        case "server_remux_hls": return "Remux (HLS)"
        case "server_transcode_hls": return "Transcode (HLS)"
        default:
            let words = delivery.replacingOccurrences(of: "_", with: " ")
            return words.isEmpty ? "Unknown" : words
        }
    }

    /// `MP4 · HEVC 3840×1600 HDR10 · AAC 2ch · 18.0 Mbps`
    var detailLine: String? {
        var parts: [String] = []
        if let container = Self.normalized(container) {
            parts.append(container.uppercased())
        }
        var video: [String] = []
        if let codec = Self.normalized(videoCodec) {
            video.append(Self.codecLabel(codec))
        }
        if let width, let height, width > 0, height > 0 {
            video.append("\(width)×\(height)")
        }
        if let range = Self.normalized(dynamicRange), range.lowercased() != "sdr" {
            video.append(Self.dynamicRangeLabel(range))
        }
        if !video.isEmpty { parts.append(video.joined(separator: " ")) }
        var audio: [String] = []
        if let codec = Self.normalized(audioCodec) {
            audio.append(Self.codecLabel(codec))
        }
        if let audioChannels, audioChannels > 0 {
            audio.append("\(audioChannels)ch")
        }
        if !audio.isEmpty { parts.append(audio.joined(separator: " ")) }
        if let bitrateKbps, bitrateKbps > 0 {
            parts.append(String(format: "%.1f Mbps", Double(bitrateKbps) / 1_000))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Planner reason as words (`audio_adaptation` → `audio adaptation`).
    var reasonLabel: String? {
        Self.normalized(reason)?.replacingOccurrences(of: "_", with: " ")
    }

    private static func codecLabel(_ codec: String) -> String {
        switch codec.lowercased() {
        case "hevc", "h265", "hvc1", "hev1": return "HEVC"
        case "h264", "avc", "avc1": return "H.264"
        case "av1": return "AV1"
        case "vp9": return "VP9"
        case "aac": return "AAC"
        case "ac3": return "AC-3"
        case "eac3": return "E-AC-3"
        case "truehd": return "TrueHD"
        case "dts": return "DTS"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        default: return codec
        }
    }

    private static func dynamicRangeLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "hdr10": return "HDR10"
        case "hdr10_plus", "hdr10+": return "HDR10+"
        case "hlg": return "HLG"
        case "dolby_vision": return "Dolby Vision"
        default: return value
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// What kind of URL the player was handed, and its path with every secret
/// removed: no query or fragment (stream tokens ride there), no user info,
/// opaque ids and signatures collapsed to `:id`, media filenames dropped.
enum PlaybackStreamPath {
    static func describe(_ url: URL?) -> String? {
        guard let url else { return nil }
        if url.isFileURL { return "Offline file" }
        let kind = isLoopback(url.host) ? "Loopback proxy" : "Remote"
        let path = redactedPath(url)
        return path.isEmpty || path == "/" ? kind : "\(kind) · \(path)"
    }

    static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "::1" || host == "[::1]" || host.hasPrefix("127.")
    }

    static func redactedPath(_ url: URL) -> String {
        let components = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { redactedComponent(String($0)) }
        return "/" + components.joined(separator: "/")
    }

    /// Keeps route words (`api`, `v2`, `live-hls`) and protocol-fixed
    /// manifest or segment names (`master.m3u8`, `seg_00042.ts`); replaces
    /// anything that looks like an id or signature with `:id` and user media
    /// filenames with `[media]`.
    static func redactedComponent(_ component: String) -> String {
        if MediaLogRedactor.isMediaFilenameComponent(component) {
            return "[media]"
        }
        if matches(component, #"^[A-Za-z]+[0-9]?$"#) && component.count <= 24 {
            return component
        }
        if matches(component, #"^[a-z]+([_-][a-z]+)+$"#) && component.count <= 24 {
            return component
        }
        if matches(component, #"^[A-Za-z][A-Za-z0-9_-]{0,23}\.(m3u8|mpd|mp4|m4s|m4a|ts|aac|vtt|webvtt)$"#) {
            return component
        }
        return ":id"
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
