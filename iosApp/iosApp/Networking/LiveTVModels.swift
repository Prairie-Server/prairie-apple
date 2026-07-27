import Foundation

// MARK: - Channels

/// Wire shape for `GET /api/v1/livetv/channels`.
struct LiveTVChannelsResponse: Codable {
    let channels: [LiveTVChannel]
}

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
    let streamUrl: String
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

// MARK: - Guide / EPG

struct LiveTVGuideResponse: Codable {
    let programs: [LiveTVProgram]
    let start: Date
    let end: Date
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

/// Response from `POST /api/v1/livetv/channels/{id}/session`.
struct LiveTVSessionStartResponse: Codable, Hashable {
    let sessionId: String
    let playbackTicket: String
    let hlsUrl: String
    let streamUrl: String?
    let transport: String?
    let note: String?

    /// Preferred client playback URL (`hls_url`, then `stream_url`).
    var playableURLString: String {
        let primary = hlsUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty { return primary }
        return streamUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

struct LiveTVSession: Codable, Hashable, Identifiable {
    let id: String
    let channelId: String
    let tunerId: String
    let tunerIndex: Int
    let userId: Int?
    let profileId: String?
    let playbackSessionId: String?
    let status: String
    let hlsUrl: String?
    let streamUrl: String?
    let note: String?
    let createdAt: Date
    let releasedAt: Date?
}

// MARK: - Recordings

struct LiveTVRecordingsResponse: Codable {
    let recordings: [LiveTVRecording]
}

struct LiveTVRecording: Codable, Hashable, Identifiable {
    let id: String
    let programId: String?
    let channelId: String
    let seriesRuleId: String?
    let status: String
    // Server may return a filesystem `path`; intentionally not decoded into UI models.
    let libraryItemId: String?
    let start: Date
    let stop: Date
    let title: String
}

/// Body for guide-based `POST /api/v1/livetv/recordings`.
/// Server resolves channel/window/title from `program_id` — do not over-post.
struct LiveTVScheduleRecordingInput: Encodable {
    let programId: String
}
