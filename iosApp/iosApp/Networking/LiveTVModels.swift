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
    let note: String?
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
