import Foundation

// MARK: - Live TV / OTA / DVR

/// Client endpoints for `/api/v1/livetv/*` (channels, guide, live session,
/// recordings). Admin tuner/guide-source management stays on the web.
extension ContinuumAPI {
    /// Channel lineup. Optional `tunerId` scopes to one tuner.
    func liveTVChannels(tunerId: String? = nil) async throws -> [LiveTVChannel] {
        var query: [String: String] = [:]
        if let tunerId, !tunerId.isEmpty {
            query["tuner_id"] = tunerId
        }
        let response: LiveTVChannelsResponse = try await http.get(
            "/api/v1/livetv/channels",
            query: query
        )
        return response.channels
    }

    /// Guide window. Omit `channelIds` for all channels; times are RFC3339.
    func liveTVGuide(
        channelIds: [String] = [],
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> LiveTVGuideResponse {
        var query: [String: String] = [:]
        if !channelIds.isEmpty {
            query["channels"] = channelIds.joined(separator: ",")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let start {
            query["start"] = formatter.string(from: start)
        }
        if let end {
            query["end"] = formatter.string(from: end)
        }
        return try await http.get("/api/v1/livetv/guide", query: query)
    }

    func liveTVProgram(id: String) async throws -> LiveTVProgram {
        try await http.get("/api/v1/livetv/programs/\(try Self.encodePathSegment(id))")
    }

    /// Start a tuner session for live HLS playback.
    func startLiveTVSession(channelId: String) async throws -> LiveTVSessionStartResponse {
        try await http.post("/api/v1/livetv/channels/\(try Self.encodePathSegment(channelId))/session")
    }

    /// Release a live session (frees the tuner). Prefer calling on player dismiss.
    func releaseLiveTVSession(sessionId: String) async throws {
        try await http.delete("/api/v1/livetv/sessions/\(try Self.encodePathSegment(sessionId))")
    }

    func liveTVRecordings(status: String? = nil) async throws -> [LiveTVRecording] {
        var query: [String: String] = [:]
        if let status, !status.isEmpty {
            query["status"] = status
        }
        let response: LiveTVRecordingsResponse = try await http.get(
            "/api/v1/livetv/recordings",
            query: query
        )
        return response.recordings
    }

    func scheduleLiveTVRecording(_ input: LiveTVScheduleRecordingInput) async throws -> LiveTVRecording {
        try await http.post("/api/v1/livetv/recordings", body: input)
    }

    func cancelLiveTVRecording(id: String) async throws {
        try await http.delete("/api/v1/livetv/recordings/\(try Self.encodePathSegment(id))")
    }

    /// Percent-encode a single path segment; reject empty ids and `/` / `..`.
    private static func encodePathSegment(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("..") else {
            throw APIError.invalidPathParameter(name: "id", value: raw)
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }
}
