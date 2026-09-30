import Foundation

// MARK: - Live TV / OTA / DVR

/// Client endpoints for `/api/v1/livetv/*` (channels, guide, live session,
/// recordings). Admin tuner/guide-source management stays on the web.
extension PrairieAPI {
    /// Channel lineup. Optional `tunerId` scopes to one tuner.
    func liveTVChannels(tunerId: String? = nil) async throws -> [LiveTVChannel] {
        var query: [String: String] = [:]
        if let tunerId, !tunerId.isEmpty {
            query["tuner_id"] = tunerId
        }
        let response: LiveTVChannelsResponse = try await liveTVRequest(
            "GET",
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
        return try await liveTVRequest("GET", "/api/v1/livetv/guide", query: query)
    }

    func liveTVProgram(id: String) async throws -> LiveTVProgram {
        try await liveTVRequest("GET", "/api/v1/livetv/programs/\(try Self.encodePathSegment(id))")
    }

    /// Start a tuner session for live HLS playback.
    func startLiveTVSession(channelId: String) async throws -> LiveTVSessionStartResponse {
        try await liveTVRequest("POST", "/api/v1/livetv/channels/\(try Self.encodePathSegment(channelId))/session")
    }

    /// Release a live session (frees the tuner). Prefer calling on player dismiss.
    func releaseLiveTVSession(sessionId: String) async throws {
        try await liveTVSend("DELETE", "/api/v1/livetv/sessions/\(try Self.encodePathSegment(sessionId))")
    }

    /// Keep the tuner claimed while the player is open, including while
    /// paused (no segment fetches). The server reclaims a session after 90 s
    /// with neither a segment fetch nor a heartbeat.
    func heartbeatLiveTVSession(sessionId: String) async throws {
        try await liveTVSend("POST", "/api/v1/livetv/sessions/\(try Self.encodePathSegment(sessionId))/heartbeat")
    }

    func liveTVRecordings(status: String? = nil) async throws -> [LiveTVRecording] {
        var query: [String: String] = [:]
        if let status, !status.isEmpty {
            query["status"] = status
        }
        let response: LiveTVRecordingsResponse = try await liveTVRequest(
            "GET",
            "/api/v1/livetv/recordings",
            query: query
        )
        return response.recordings
    }

    func scheduleLiveTVRecording(_ input: LiveTVScheduleRecordingInput) async throws -> LiveTVRecording {
        try await liveTVRequest("POST", "/api/v1/livetv/recordings", body: try JSONEncoder.liveTV.encode(input))
    }

    func cancelLiveTVRecording(id: String) async throws {
        try await liveTVSend("DELETE", "/api/v1/livetv/recordings/\(try Self.encodePathSegment(id))")
    }

    /// Percent-encode a single path segment; reject empty ids and `/` / `..`.
    private static func encodePathSegment(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("..") else {
            throw LiveTVAPIError.invalidPathParameter(name: "id", value: raw)
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }

    // MARK: - Transport

    /// Live TV stays on the Prairie-only `/api/v1/livetv` routes, so it
    /// sends through `HTTPClient.requestData` (auth, refresh, diagnostics)
    /// instead of the typed API v2 client.
    private func liveTVRequest<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: Data? = nil
    ) async throws -> T {
        let response = try await http.requestData(method: method, path: path, query: query, body: body)
        do {
            return try HTTPClient.makeJSONDecoder(artworkServerURL: response.url)
                .decode(T.self, from: response.data)
        } catch {
            throw HTTPError.decodingFailed(type: String(describing: T.self), underlying: error)
        }
    }

    private func liveTVSend(_ method: String, _ path: String) async throws {
        _ = try await http.requestData(method: method, path: path)
    }
}

enum LiveTVAPIError: LocalizedError {
    case invalidPathParameter(name: String, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidPathParameter(let name, let value):
            return "Invalid \(name): \(value)"
        }
    }
}

private extension JSONEncoder {
    /// Snake-case bodies, matching the server's Go JSON tags.
    static var liveTV: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
