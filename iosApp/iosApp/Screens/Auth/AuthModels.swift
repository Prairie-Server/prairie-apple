import Foundation

/// Server setup status from /api/v1/auth/setup.
struct SetupStatus: Codable {
    let needsSetup: Bool
}

/// Signup status from /api/v1/auth/signup.
struct SignupStatus: Codable {
    let enabled: Bool
}

/// Liveness + identity probe from GET /api/v1/health.
///
/// The server returns `{"status": "ok"}` always; `serverName` and
/// `serverId` are populated from server config and used by the multi-
/// server picker to show a friendly name for each saved server.
/// Both identity fields are optional to remain compatible with older
/// servers that predate the identity addition.
struct HealthStatus: Codable {
    let status: String
    let serverName: String?
    let serverId: String?
}
