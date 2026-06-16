import Foundation
import Network

actor SiloCastSession {
    enum SessionError: Error {
        case closed
    }

    private let connection: NWConnection
    private var frameBuffer = PairingFrameBuffer()
    private var continuation: AsyncThrowingStream<SiloCastMessage, Error>.Continuation?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isOpen = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    init(endpoint: NWEndpoint) {
        connection = NWConnection(to: endpoint, using: Self.tlsParameters())
    }

    static func tlsParameters() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let pskData = Data("silo-cast-v1".utf8)
        let identityData = Data("silo-cast".utf8)
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

    func open() -> AsyncThrowingStream<SiloCastMessage, Error> {
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
            self.connection.start(queue: .main)
        }
    }

    func send(_ message: SiloCastMessage) async throws {
        guard isOpen else { throw SessionError.closed }
        let payload = try encoder.encode(message)
        let framed = try PairingFrame.encode(payload)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    func close() {
        teardown(nil)
    }

    private func teardown(_ error: Error?) {
        guard isOpen else { return }
        isOpen = false
        connection.cancel()
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
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
                    let message = try decoder.decode(SiloCastMessage.self, from: payload)
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
