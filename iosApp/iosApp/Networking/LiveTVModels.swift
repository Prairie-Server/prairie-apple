import Foundation

// MARK: - Channels

/// Wire shape for API v2 `{items}` list envelopes.
struct LiveTVItemsResponse<Item: Decodable>: Decodable {
    let items: [Item]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
    }

    private enum CodingKeys: String, CodingKey { case items }
}

/// Channel from `GET /api/v2/livetv/channels`. v2 no longer carries a
/// `stream_url`; start a session to play. Decoding tolerates missing fields.
struct LiveTVChannel: Codable, Hashable, Identifiable {
    let id: String
    let tunerId: String
    let number: String
    let numberOverride: String?
    let callsign: String
    let name: String
    let logoUrl: String
    let hd: Bool
    let enabled: Bool
    let guideStationId: String

    /// Display number preferring an admin override when present.
    var displayNumber: String {
        let override = numberOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? number : override
    }

    /// Prefer callsign, then name, then the display number.
    var displayName: String {
        let call = callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        if !call.isEmpty { return call }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return displayNumber
    }
}

extension LiveTVChannel {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        tunerId = try c.decodeIfPresent(String.self, forKey: .tunerId) ?? ""
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        numberOverride = try c.decodeIfPresent(String.self, forKey: .numberOverride)
        callsign = try c.decodeIfPresent(String.self, forKey: .callsign) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl) ?? ""
        hd = try c.decodeIfPresent(Bool.self, forKey: .hd) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        guideStationId = try c.decodeIfPresent(String.self, forKey: .guideStationId) ?? ""
    }
}

// MARK: - Guide / EPG

/// Wire shape for `GET /api/v2/livetv/guide`: `{items, start, end}`.
struct LiveTVGuideResponse: Codable {
    let items: [LiveTVProgram]
    let start: Date?
    let end: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([LiveTVProgram].self, forKey: .items) ?? []
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
    }
}

struct LiveTVProgram: Codable, Hashable, Identifiable {
    let id: String
    let channelId: String
    let sourceId: String?
    let seriesId: String
    let externalId: String?
    let start: Date
    let stop: Date
    let title: String
    let subtitle: String
    let description: String
    let season: Int?
    let episode: Int?
    let genres: [String]
    let imageUrl: String
    let isNew: Bool
    let isLive: Bool

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}

extension LiveTVProgram {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId) ?? ""
        sourceId = try c.decodeIfPresent(String.self, forKey: .sourceId)
        seriesId = try c.decodeIfPresent(String.self, forKey: .seriesId) ?? ""
        externalId = try c.decodeIfPresent(String.self, forKey: .externalId)
        start = try c.decode(Date.self, forKey: .start)
        stop = try c.decode(Date.self, forKey: .stop)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        season = try c.decodeIfPresent(Int.self, forKey: .season)
        episode = try c.decodeIfPresent(Int.self, forKey: .episode)
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl) ?? ""
        isNew = try c.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
    }
}

/// Now + next slot derived from a guide window for one channel.
struct LiveTVNowNext: Hashable {
    var now: LiveTVProgram?
    var next: LiveTVProgram?

    init(now: LiveTVProgram? = nil, next: LiveTVProgram? = nil) {
        self.now = now
        self.next = next
    }
}

// MARK: - Live session

/// Optional body for `POST /api/v2/livetv/channels/{id}/sessions`.
struct LiveTVSessionStartInput: Encodable, Equatable {
    let clientCapabilities: LiveTVClientCapabilities?
}

/// What the native live player decodes, so the server transcodes only what
/// AVPlayer can't play (broadcast MPEG-2 video, for example).
struct LiveTVClientCapabilities: Encodable, Equatable {
    let codecsVideo: [String]
    let codecsAudio: [String]
    let audioPassthroughCodecs: [String]
    let maxAudioChannels: Int
    let maxResolution: String

    /// AVPlayer over HLS: H.264/HEVC video, AAC/AC-3/E-AC-3 audio up to 5.1.
    static var avPlayer: LiveTVClientCapabilities {
        LiveTVClientCapabilities(
            codecsVideo: ["h264", "hevc"],
            codecsAudio: ["aac", "ac3", "eac3"],
            audioPassthroughCodecs: [],
            maxAudioChannels: 6,
            maxResolution: AppleDecodeCapabilities.maxResolutionToken
        )
    }
}

/// Response from `POST /api/v2/livetv/channels/{id}/sessions` (201).
/// `stream_url` replaces v1's `hls_url`; play it exactly as returned.
struct LiveTVSessionStartResponse: Codable, Hashable {
    let sessionId: String
    let channelId: String?
    let playbackTicket: String?
    let streamUrl: String
    let transport: String?
    let note: String?
    let status: String?
    let staleAfterSeconds: Int?

    init(
        sessionId: String,
        channelId: String? = nil,
        playbackTicket: String? = nil,
        streamUrl: String,
        transport: String? = nil,
        note: String? = nil,
        status: String? = nil,
        staleAfterSeconds: Int? = nil
    ) {
        self.sessionId = sessionId
        self.channelId = channelId
        self.playbackTicket = playbackTicket
        self.streamUrl = streamUrl
        self.transport = transport
        self.note = note
        self.status = status
        self.staleAfterSeconds = staleAfterSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        playbackTicket = try c.decodeIfPresent(String.self, forKey: .playbackTicket)
        streamUrl = try c.decodeIfPresent(String.self, forKey: .streamUrl) ?? ""
        transport = try c.decodeIfPresent(String.self, forKey: .transport)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        staleAfterSeconds = try c.decodeIfPresent(Int.self, forKey: .staleAfterSeconds)
    }

    /// Client playback URL: the server's opaque `stream_url`.
    var playableURLString: String {
        streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether AVPlayer should treat the session as HLS. Explicit `transport=hls`
    /// wins; remuxed `live-hls` / `.m3u8` URLs count even when transport says
    /// `mpegts` (server bridge always serves HLS to native clients).
    var isHLS: Bool {
        let normalized = transport?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if normalized == "hls" { return true }
        let url = playableURLString.lowercased()
        if url.contains(".m3u8") || url.contains("live-hls") { return true }
        if normalized == "mpegts" { return false }
        return false
    }
}

/// Turns server-supplied Live TV stream paths into absolute URLs.
enum LiveTVURLResolver {
    /// Mirrors SmartTV `resolveLivePlaybackUrl` / `buildStreamUrl`: resolve
    /// against the active server, then attach `token` + `profile_id` query
    /// params for same-origin streams so AVPlayer segment fetches stay authed.
    nonisolated static func resolve(
        _ raw: String,
        serverBaseURL: String,
        accessToken: String? = nil,
        profileId: String? = nil
    ) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolved: URL?
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            resolved = URL(string: trimmed)
        } else {
            let base = serverBaseURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !base.isEmpty else { return nil }

            let relativePath = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
            let urlString = relativePath.hasPrefix("/api/")
                ? "\(base)\(relativePath)"
                : "\(base)/api/v1\(relativePath)"
            resolved = URL(string: urlString)
        }

        guard let resolved else { return nil }
        guard isSameServerOrigin(serverBaseURL: serverBaseURL, candidate: resolved) else {
            return resolved
        }
        return appendAuthQuery(to: resolved, accessToken: accessToken, profileId: profileId)
    }

    nonisolated private static func isSameServerOrigin(serverBaseURL: String, candidate: URL) -> Bool {
        let trimmed = serverBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let server = URL(string: trimmed) else { return false }
        guard let serverHost = server.host, let candidateHost = candidate.host else { return false }
        return server.scheme == candidate.scheme && serverHost == candidateHost
    }

    nonisolated private static func appendAuthQuery(
        to url: URL,
        accessToken: String?,
        profileId: String?
    ) -> URL {
        let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profile = profileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty || !profile.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var items = components.queryItems ?? []
        if !token.isEmpty {
            items.removeAll { $0.name == "token" }
            items.append(URLQueryItem(name: "token", value: token))
        }
        if !profile.isEmpty {
            items.removeAll { $0.name == "profile_id" }
            items.append(URLQueryItem(name: "profile_id", value: profile))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? url
    }
}

// MARK: - Recordings

/// Recording from `GET /api/v2/livetv/recordings`. v2 dropped `user_id` and
/// `path`; `start`/`stop` are optional.
struct LiveTVRecording: Codable, Hashable, Identifiable {
    let id: String
    let programId: String?
    let channelId: String
    let seriesRuleId: String?
    let profileId: String?
    let status: String
    let libraryItemId: String?
    let start: Date?
    let stop: Date?
    let title: String
    let lastError: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        programId = try c.decodeIfPresent(String.self, forKey: .programId)
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId) ?? ""
        seriesRuleId = try c.decodeIfPresent(String.self, forKey: .seriesRuleId)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        libraryItemId = try c.decodeIfPresent(String.self, forKey: .libraryItemId)
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        stop = try c.decodeIfPresent(Date.self, forKey: .stop)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
    }
}

/// Body for guide-based `POST /api/v2/livetv/recordings`.
/// Server resolves channel/window/title from `program_id` — do not over-post.
struct LiveTVScheduleRecordingInput: Encodable {
    let programId: String
}
