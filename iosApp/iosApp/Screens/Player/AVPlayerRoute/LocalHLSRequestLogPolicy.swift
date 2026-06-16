import Foundation

enum LocalHLSRequestLogPolicy {
    static func shouldLog(
        status: Int,
        requestLogCount: Int,
        startupRequestLogLimit: Int,
        signatureAlreadyLogged: Bool
    ) -> Bool {
        guard !signatureAlreadyLogged else { return false }
        guard status < 400 else { return true }
        return requestLogCount < startupRequestLogLimit
    }
}
