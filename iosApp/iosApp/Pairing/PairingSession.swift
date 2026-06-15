import Foundation
import Network

/// Wraps one `NWConnection` carrying framed `PairingMessage`s. Both the
/// Companion (outbound) and Receiver (inbound) sides use this. TLS provides
/// opportunistic confidentiality only (the cert is unauthenticated — see the
/// design spec §6); integrity rests on the server-issued match code.
actor PairingSession {
    enum SessionError: Error { case closed }

    private let connection: NWConnection
    private var frameBuffer = PairingFrameBuffer()
    private var continuation: AsyncThrowingStream<PairingMessage, Error>.Continuation?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isOpen = false

    /// Inbound side (Receiver): wrap a connection handed up by `NWListener`.
    init(connection: NWConnection) {
        self.connection = connection
    }

    /// Outbound side (Companion): connect to a discovered endpoint over TLS.
    init(endpoint: NWEndpoint) {
        let params = PairingSession.tlsParameters()
        self.connection = NWConnection(to: endpoint, using: params)
    }

    static func tlsParameters() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        // Opportunistic confidentiality only (design spec §6): a FIXED, non-secret
        // pre-shared key compiled into the app. NOT an authentication boundary —
        // the key is in the binary; the server-issued match code is the trust
        // anchor. A PSK lets both the tvOS NWListener and the iOS NWConnection
        // negotiate TLS without certificate/identity management.
        let pskData = Data("silo-companion-pairing-v1".utf8)
        let identityData = Data("silo-pairing".utf8)
        let key = pskData.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = identityData.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions,
            key as __DispatchData,
            identity as __DispatchData
        )
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t.AES_128_GCM_SHA256
        )
        let tcp = NWProtocolTCP.Options()
        let params = NWParameters(tls: tls, tcp: tcp)
        params.includePeerToPeer = true
        return params
    }

    /// Start the connection and begin the receive loop. Returns a stream of
    /// decoded inbound messages; the stream finishes on close and throws on
    /// transport/decode error.
    func open() -> AsyncThrowingStream<PairingMessage, Error> {
        guard !isOpen else { return AsyncThrowingStream { $0.finish() } }
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            self.isOpen = true
            self.connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Task { await self.receiveLoop() }
                case .failed(let error):
                    Task { await self.teardown(error) }
                case .waiting:
                    // Transient for an outbound connection (no route yet,
                    // Wi-Fi associating, peer-to-peer bring-up). NW keeps
                    // retrying and can still reach `.ready`, so don't finish.
                    break
                case .cancelled:
                    Task { await self.teardown(nil) }
                default:
                    break
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.close() }
            }
            self.connection.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Encode and send one message as a single frame. Caller-serialized:
    /// only one send may be outstanding at a time.
    func send(_ message: PairingMessage) async throws {
        guard isOpen else { throw SessionError.closed }
        let payload = try encoder.encode(message)
        let framed = try PairingFrame.encode(payload)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    func close() {
        teardown(nil)
    }

    /// Single terminal-exit path for every code site (explicit close, `.failed`,
    /// `.cancelled`, receive error, EOF). Idempotent — the `isOpen` guard also
    /// breaks the cancel → `.cancelled` → teardown recursion.
    private func teardown(_ error: Error?) {
        guard isOpen else { return }
        isOpen = false
        connection.cancel()
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
        continuation = nil
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { await self.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: Error?) {
        guard isOpen, continuation != nil else { return }
        if let error {
            teardown(error)
            return
        }
        if let data, !data.isEmpty {
            do {
                for payload in try frameBuffer.append(data) {
                    let message = try decoder.decode(PairingMessage.self, from: payload)
                    continuation?.yield(message)
                }
            } catch {
                teardown(error)
                return
            }
        }
        if isComplete {
            teardown(nil)
            return
        }
        receiveLoop()
    }
}
