import Foundation

/// Device-authorization calls issued against an EXPLICIT server base URL,
/// independent of the app's single active server. Used by both pairing sides:
/// the Receiver calls start/poll against a pushed URL (no auth); the Companion
/// calls lookup/approve against a chosen server (bearer = that server's token).
struct PairingDeviceAPI {
    enum APIError: Error { case badURL, http(Int), decode }

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: Receiver (unauthenticated)

    func start(serverURL: String, deviceName: String, devicePlatform: String) async throws -> DeviceLoginStartResponse {
        try await post(serverURL, "/api/v1/auth/device/start", bearer: nil,
                       body: DeviceLoginStartRequest(deviceName: deviceName, devicePlatform: devicePlatform))
    }

    func poll(serverURL: String, deviceCode: String) async throws -> DeviceLoginPollResponse {
        try await post(serverURL, "/api/v1/auth/device/poll", bearer: nil,
                       body: DeviceLoginPollRequest(deviceCode: deviceCode))
    }

    // MARK: Companion (authenticated with the chosen server's token)

    func lookup(serverURL: String, bearer: String, userCode: String) async throws -> DeviceLookupResponse {
        try await get(serverURL, "/api/v1/auth/device", query: ["code": userCode], bearer: bearer)
    }

    func approve(serverURL: String, bearer: String, userCode: String) async throws {
        let _: EmptyResponse = try await post(serverURL, "/api/v1/auth/device/approve",
                                              bearer: bearer, body: DeviceApproveRequest(code: userCode))
    }

    private struct EmptyResponse: Codable {}

    // MARK: Transport

    private func get<R: Decodable>(_ serverURL: String, _ path: String, query: [String: String], bearer: String?) async throws -> R {
        guard var comps = URLComponents(string: serverURL.appending(path)) else { throw APIError.badURL }
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request, bearer: bearer)
        return try await send(request)
    }

    private func post<B: Encodable, R: Decodable>(_ serverURL: String, _ path: String, bearer: String?, body: B) async throws -> R {
        guard let url = URL(string: serverURL.appending(path)) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        applyHeaders(&request, bearer: bearer)
        return try await send(request)
    }

    private func applyHeaders(_ request: inout URLRequest, bearer: String?) {
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let device = AppleDeviceIdentity.current
        request.setValue(device.id, forHTTPHeaderField: "X-Silo-Device-Id")
        request.setValue(device.name, forHTTPHeaderField: "X-Silo-Device-Name")
        request.setValue(device.platform, forHTTPHeaderField: "X-Silo-Device-Platform")
    }

    private func send<R: Decodable>(_ request: URLRequest) async throws -> R {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        if R.self == EmptyResponse.self { return EmptyResponse() as! R }
        do { return try decoder.decode(R.self, from: data) }
        catch { throw APIError.decode }
    }
}
