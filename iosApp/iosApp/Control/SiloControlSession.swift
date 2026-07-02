import Foundation
import Network

actor SiloControlSession {
    enum SessionError: Error {
        case closed
    }

    private let connection: NWConnection
    private var frameBuffer = PairingFrameBuffer()
    private var continuation: AsyncThrowingStream<SiloControlMessage, Error>.Continuation?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isOpen = false

    // Ordered outbound queue: enqueue() is nonisolated + FIFO; a single drain
    // task sends one frame at a time so messages never reorder. `send()` goes
    // through the SAME queue (carrying a completion continuation) so an awaited
    // send — hello/launch — can't race ahead of, or behind, an enqueued
    // control/ping frame.
    private struct OutboundItem {
        let message: SiloControlMessage
        let completion: CheckedContinuation<Void, Error>?
    }
    private let outbound: AsyncStream<OutboundItem>
    private let outboundContinuation: AsyncStream<OutboundItem>.Continuation
    private var drainTask: Task<Void, Never>?

    init(connection: NWConnection) {
        self.connection = connection
        (outbound, outboundContinuation) = AsyncStream.makeStream()
    }

    init(endpoint: NWEndpoint) {
        connection = NWConnection(to: endpoint, using: Self.tlsParameters())
        (outbound, outboundContinuation) = AsyncStream.makeStream()
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

    func open() -> AsyncThrowingStream<SiloControlMessage, Error> {
        guard !isOpen else { return AsyncThrowingStream { $0.finish() } }
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            self.isOpen = true
            self.connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Task { await self.beginLoops() }
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

    private func beginLoops() {
        receiveLoop()
        drainTask = Task { [weak self] in await self?.startDrainLoop() }
    }

    /// Fire-and-forget, ordered. Safe to call from any context; FIFO is
    /// preserved by call order because all call sites are @MainActor.
    nonisolated func enqueue(_ message: SiloControlMessage) {
        outboundContinuation.yield(OutboundItem(message: message, completion: nil))
    }

    private func startDrainLoop() async {
        for await item in outbound {
            guard isOpen else {
                item.completion?.resume(throwing: SessionError.closed)
                continue
            }
            do {
                try await writeRaw(item.message)
                item.completion?.resume()
            } catch {
                item.completion?.resume(throwing: error)
                teardown(error)
                // Keep draining after teardown: the `guard isOpen` branch fails
                // any already-queued sends fast instead of leaving their
                // awaiters hung. The loop ends when `teardown` finishes the
                // stream and the buffered items drain.
            }
        }
    }

    /// Awaited, ordered send. Routes through the same FIFO as `enqueue` so the
    /// write can't reorder relative to queued frames, and surfaces the write
    /// result to the caller.
    func send(_ message: SiloControlMessage) async throws {
        guard isOpen else { throw SessionError.closed }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            outboundContinuation.yield(OutboundItem(message: message, completion: cont))
        }
    }

    private func writeRaw(_ message: SiloControlMessage) async throws {
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

    /// Send a final `.close` (ordered after any pending sends) and await the
    /// write before tearing down, so the frame is handed to the transport
    /// ahead of the FIN. The peer must read `.close` before EOF to tell a
    /// deliberate disconnect from a dropped connection — otherwise it
    /// auto-reconnects. Bounded by a watchdog so a wedged connection can't
    /// hang the caller: if the write hasn't completed in time, tear down
    /// anyway (the send continuation is then failed by the drain loop).
    func closeGracefully() async {
        guard isOpen else { return }
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.close()
        }
        try? await send(.close)
        watchdog.cancel()
        teardown(nil)
    }

    private func teardown(_ error: Error?) {
        guard isOpen else { return }
        isOpen = false
        connection.cancel()
        // Don't cancel the drain task — finishing the stream lets it drain any
        // buffered items and resume their `send` continuations with
        // `SessionError.closed` (the `guard isOpen` branch) instead of leaking
        // a hung awaiter. The task self-completes once the buffer empties.
        drainTask = nil
        outboundContinuation.finish()
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
                    let message = try decoder.decode(SiloControlMessage.self, from: payload)
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
