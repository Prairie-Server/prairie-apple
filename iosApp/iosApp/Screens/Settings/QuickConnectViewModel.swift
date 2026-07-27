import Foundation
import Observation

/// Approves another device's Quick Connect / device-login request by typing
/// the short code shown on that device (Jellyfin-style authorizer UX).
@MainActor
@Observable
final class QuickConnectViewModel {
    enum Phase: Equatable {
        case enterCode
        case loading
        case ready
        case completed(approved: Bool)
    }

    var codeInput: String = ""
    var phase: Phase = .enterCode
    var lookup: DeviceLookupResponse?
    var errorMessage: String?
    var isSubmitting = false

    private let api: PairingDeviceAPI
    private let auth: AuthService

    init(api: PairingDeviceAPI = PairingDeviceAPI(), auth: AuthService = .shared) {
        self.api = api
        self.auth = auth
    }

    var normalizedCode: String {
        Self.normalizeCode(codeInput)
    }

    var canLookup: Bool {
        normalizedCode.replacingOccurrences(of: "-", with: "").count == 8
    }

    var canDecide: Bool {
        phase == .ready && lookup?.status == "pending" && !isSubmitting
    }

    func lookupDevice() async {
        errorMessage = nil
        guard canLookup else {
            errorMessage = "Enter the full 8-character code from the other device."
            return
        }
        let serverURL = auth.serverUrl
        guard !serverURL.isEmpty else {
            errorMessage = "No active server."
            return
        }
        guard let bearer = await TokenStore.shared.getAccessToken(), !bearer.isEmpty else {
            errorMessage = "Sign in again to approve devices."
            return
        }

        phase = .loading
        do {
            let result = try await api.lookup(serverURL: serverURL, bearer: bearer, userCode: normalizedCode)
            lookup = result
            if result.status == "pending" {
                phase = .ready
            } else if result.status == "approved" || result.status == "consumed" {
                phase = .completed(approved: true)
            } else if result.status == "denied" {
                phase = .completed(approved: false)
            } else {
                phase = .ready
                errorMessage = "This request is no longer pending."
            }
        } catch {
            phase = .enterCode
            lookup = nil
            errorMessage = "Device request not found or expired."
        }
    }

    func approve() async {
        await decide(approve: true)
    }

    func deny() async {
        await decide(approve: false)
    }

    func reset() {
        codeInput = ""
        lookup = nil
        errorMessage = nil
        isSubmitting = false
        phase = .enterCode
    }

    private func decide(approve: Bool) async {
        guard canDecide else { return }
        let serverURL = auth.serverUrl
        guard let bearer = await TokenStore.shared.getAccessToken(), !bearer.isEmpty else {
            errorMessage = "Sign in again to approve devices."
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            if approve {
                try await api.approve(serverURL: serverURL, bearer: bearer, userCode: normalizedCode)
            } else {
                try await api.deny(serverURL: serverURL, bearer: bearer, userCode: normalizedCode)
            }
            phase = .completed(approved: approve)
        } catch {
            errorMessage = approve ? "Could not approve this device." : "Could not deny this device."
        }
    }

    static func normalizeCode(_ value: String) -> String {
        let clean = value
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(8)
        let chars = Array(clean)
        if chars.count <= 4 {
            return String(chars)
        }
        return String(chars.prefix(4)) + "-" + String(chars.dropFirst(4))
    }
}
