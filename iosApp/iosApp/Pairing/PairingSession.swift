import Foundation
import Network

/// Wraps one `NWConnection` carrying framed `PairingMessage`s. Both the
/// Companion (outbound) and Receiver (inbound) sides use this. TLS provides
/// opportunistic confidentiality only (the cert is unauthenticated — see the
/// design spec §6); integrity rests on the server-issued match code.
actor PairingSession {
    enum SessionError: Error { case closed, decodeFailed }

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

    /// A TLS-over-TCP parameter set with an ephemeral, unauthenticated cert.
    /// `includePeerToPeer` lets discovery/transport use AWDL when available.
    static func tlsParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        let tls = NWProtocolTLS.Options()
        let params = NWParameters(tls: tls, tcp: tcp)
        params.includePeerToPeer = true
        return params
    }

    /// Start the connection and begin the receive loop. Returns a stream of
    /// decoded inbound messages; the stream finishes on close and throws on
    /// transport/decode error.
    func open() -> AsyncThrowingStream<PairingMessage, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            self.isOpen = true
            self.connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Task { await self.receiveLoop() }
                case .failed(let error), .waiting(let error):
                    continuation.finish(throwing: error)
                case .cancelled:
                    continuation.finish()
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

    /// Encode and send one message as a single frame.
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
        guard isOpen else { return }
        isOpen = false
        connection.cancel()
        continuation?.finish()
        continuation = nil
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { await self.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: Error?) {
        if let error {
            continuation?.finish(throwing: error)
            return
        }
        if let data, !data.isEmpty {
            do {
                for payload in try frameBuffer.append(data) {
                    let message = try decoder.decode(PairingMessage.self, from: payload)
                    continuation?.yield(message)
                }
            } catch {
                continuation?.finish(throwing: error)
                return
            }
        }
        if isComplete {
            continuation?.finish()
            return
        }
        guard isOpen else { return }
        receiveLoop()
    }
}
