import Foundation

// MARK: - Live TV / OTA / DVR

/// Client endpoints for `/api/v2/livetv/*` (channels, guide, live session,
/// recordings). Admin tuner/guide-source management stays on the web.
/// Live media itself stays on the v1 URLs the server returns as `stream_url`.
extension PrairieAPI {
    /// Channel lineup. Optional `tunerId` scopes to one tuner.
    func liveTVChannels(tunerId: String? = nil) async throws -> [LiveTVChannel] {
        var query: [String: String] = [:]
        if let tunerId, !tunerId.isEmpty {
            query["tuner_id"] = tunerId
        }
        let response: LiveTVItemsResponse<LiveTVChannel> = try await liveTVRequest(
            "GET",
            "/api/v2/livetv/channels",
            query: query
        )
        return response.items
    }

    /// Guide window. Omit `channelIds` for all channels; times are RFC3339.
    /// The server caps a request at 500 `channel_id`s and a 7-day window.
    func liveTVGuide(
        channelIds: [String] = [],
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> LiveTVGuideResponse {
        var query: [String: String] = [:]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let start {
            query["start"] = formatter.string(from: start)
        }
        if let end {
            query["end"] = formatter.string(from: end)
        }
        // ponytail: lineups beyond 500 channels get the first 500; page if that ever matters.
        let repeated = channelIds.prefix(500).map { URLQueryItem(name: "channel_id", value: $0) }
        return try await liveTVRequest("GET", "/api/v2/livetv/guide", query: query, repeatedQuery: repeated)
    }

    func liveTVProgram(id: String) async throws -> LiveTVProgram {
        try await liveTVRequest("GET", "/api/v2/livetv/programs/\(try Self.encodePathSegment(id))")
    }

    /// Start a tuner session. Play the returned `stream_url` as is.
    func startLiveTVSession(
        channelId: String,
        capabilities: LiveTVClientCapabilities? = .avPlayer
    ) async throws -> LiveTVSessionStartResponse {
        try await liveTVRequest(
            "POST",
            "/api/v2/livetv/channels/\(try Self.encodePathSegment(channelId))/sessions",
            body: try JSONEncoder.liveTV.encode(LiveTVSessionStartInput(clientCapabilities: capabilities))
        )
    }

    /// Release a live session (frees the tuner). Prefer calling on player dismiss.
    func releaseLiveTVSession(sessionId: String) async throws {
        try await liveTVSend("DELETE", "/api/v2/livetv/sessions/\(try Self.encodePathSegment(sessionId))")
    }

    /// Keep the tuner claimed while the player is open, including while
    /// paused (no segment fetches). The server reclaims a session after
    /// `stale_after_seconds` (90) with neither a segment fetch nor a heartbeat.
    func heartbeatLiveTVSession(sessionId: String) async throws {
        try await liveTVSend("POST", "/api/v2/livetv/sessions/\(try Self.encodePathSegment(sessionId))/heartbeat")
    }

    func liveTVRecordings(status: String? = nil) async throws -> [LiveTVRecording] {
        var query: [String: String] = [:]
        if let status, !status.isEmpty {
            query["status"] = status
        }
        let response: LiveTVItemsResponse<LiveTVRecording> = try await liveTVRequest(
            "GET",
            "/api/v2/livetv/recordings",
            query: query
        )
        return response.items
    }

    func scheduleLiveTVRecording(_ input: LiveTVScheduleRecordingInput) async throws -> LiveTVRecording {
        try await liveTVRequest("POST", "/api/v2/livetv/recordings", body: try JSONEncoder.liveTV.encode(input))
    }

    func cancelLiveTVRecording(id: String) async throws {
        try await liveTVSend("DELETE", "/api/v2/livetv/recordings/\(try Self.encodePathSegment(id))")
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

    /// Sends through `HTTPClient.requestData` (auth, refresh, diagnostics).
    private func liveTVRequest<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        repeatedQuery: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> T {
        let response: HTTPRawResponse
        do {
            response = try await http.requestData(
                method: method,
                path: path,
                query: query,
                repeatedQuery: repeatedQuery,
                body: body
            )
        } catch {
            throw LiveTVAPIError.mapping(error)
        }
        do {
            return try HTTPClient.makeJSONDecoder(artworkServerURL: response.url)
                .decode(T.self, from: response.data)
        } catch {
            throw HTTPError.decodingFailed(type: String(describing: T.self), underlying: error)
        }
    }

    /// For operations answered with 204 (heartbeat, stop) or a body we ignore.
    private func liveTVSend(_ method: String, _ path: String) async throws {
        do {
            _ = try await http.requestData(method: method, path: path)
        } catch {
            throw LiveTVAPIError.mapping(error)
        }
    }
}

enum LiveTVAPIError: LocalizedError, Equatable {
    case invalidPathParameter(name: String, value: String)
    /// 409 `capability_not_configured`: Live TV is off on this server.
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidPathParameter(let name, let value):
            return "Invalid \(name): \(value)"
        case .unavailable:
            return "Live TV unavailable"
        }
    }

    /// Maps the "Live TV is off" problem to ``unavailable``; other errors
    /// (including 409 "no tuner free") pass through unchanged.
    static func mapping(_ error: Error) -> Error {
        if case HTTPError.http(409, let body) = error,
           body?.contains("capability_not_configured") == true {
            return LiveTVAPIError.unavailable
        }
        return error
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
