#if os(iOS)
import Foundation

@MainActor
@Observable
final class SiloCastController {
    private(set) var activeTarget: SiloCastTarget?
    private(set) var state: SiloCastPlaybackState?
    private(set) var isConnecting = false
    var errorMessage: String?
    var isShowingRemoteControl = false

    let clock = RemotePlaybackClock()

    private var session: SiloCastSession?
    private var readTask: Task<Void, Never>?
    private var connectionId: UUID?

    private(set) var isReconnecting = false
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var missedHeartbeats = 0
    private var lastTarget: SiloCastTarget?
    private static let heartbeatInterval: Duration = .seconds(3)
    private static let maxMissedHeartbeats = 3
    private static let maxReconnectAttempts = 5

    var hasActiveSession: Bool {
        session != nil && activeTarget != nil
    }

    @discardableResult
    func connect(to target: SiloCastTarget, isReconnectAttempt: Bool = false) async -> Bool {
        guard let activeServerId = ServerRegistry.shared.activeServerId else {
            errorMessage = "Choose a server before casting."
            return false
        }
        guard target.serverId == activeServerId else {
            errorMessage = "That TV is connected to a different server."
            return false
        }

        if !isReconnectAttempt {
            reconnectTask?.cancel()
            reconnectTask = nil
            isReconnecting = false
        }

        if activeTarget?.id == target.id, session != nil {
            errorMessage = nil
            isShowingRemoteControl = true
            return true
        }

        await closeCurrentSession(sendClose: false)

        isConnecting = true
        errorMessage = nil
        activeTarget = target
        lastTarget = target
        state = nil
        isShowingRemoteControl = true

        let session = SiloCastSession(endpoint: target.endpoint)
        let connectionId = UUID()
        self.session = session
        self.connectionId = connectionId
        let stream = await session.open()
        startReadLoop(stream: stream, connectionId: connectionId)
        startHeartbeat(connectionId: connectionId)

        do {
            try await session.send(makeHello())
        } catch {
            fail(error.localizedDescription, connectionId: connectionId)
            return false
        }
        isConnecting = false
        return self.connectionId == connectionId && self.session != nil
    }

    func cast(to target: SiloCastTarget, request: SiloCastPlaybackRequest) async {
        guard await connect(to: target) else { return }
        await launch(request)
    }

    func launch(_ request: SiloCastPlaybackRequest) async {
        guard let activeServerId = ServerRegistry.shared.activeServerId else {
            errorMessage = "Choose a server before casting."
            return
        }
        guard let session, activeTarget != nil else {
            errorMessage = "Choose a TV from Home before playing."
            return
        }

        isConnecting = true
        errorMessage = nil
        isShowingRemoteControl = true

        let connectionId = self.connectionId
        do {
            try await session.send(.launch(SiloCastLaunchRequest(serverId: activeServerId, playback: request)))
            isConnecting = false
        } catch {
            fail(error.localizedDescription, connectionId: connectionId)
        }
    }

    func send(_ command: SiloCastControlCommand) {
        session?.enqueue(.control(command))
    }

    func togglePlayPauseOptimistic() {
        clock.setOptimisticPlaying(!clock.isPlaying)
        send(.playPause)
    }

    func seekOptimistic(to seconds: Double) {
        clock.setOptimisticTime(seconds)
        send(.seek(seconds: seconds))
    }

    func playNext() { send(.playNext) }
    func setVolume(_ v: Double) { send(.setVolume(min(max(v, 0), 1))) }
    func setMuted(_ m: Bool) { send(.setMuted(m)) }

    func hideRemoteControl() {
        isShowingRemoteControl = false
    }

    func showRemoteControl() {
        guard hasActiveSession else { return }
        isShowingRemoteControl = true
    }

    func turnOffControlMode() {
        disconnect()
    }

    func disconnect() {
        let session = self.session
        Task {
            if let session {
                try? await session.send(.close)
                await session.close()
            }
        }
        clearSession()
    }

    private func startReadLoop(
        stream: AsyncThrowingStream<SiloCastMessage, Error>,
        connectionId: UUID
    ) {
        readTask?.cancel()
        readTask = Task { [weak self] in
            do {
                for try await message in stream {
                    await MainActor.run { self?.handle(message, connectionId: connectionId) }
                }
                await MainActor.run {
                    guard self?.connectionId == connectionId else { return }
                    self?.beginReconnect(reason: "Lost connection to the TV.")
                }
            } catch {
                await MainActor.run {
                    guard self?.connectionId == connectionId else { return }
                    self?.beginReconnect(reason: error.localizedDescription)
                }
            }
        }
    }

    private func handle(_ message: SiloCastMessage, connectionId: UUID) {
        guard self.connectionId == connectionId else { return }
        missedHeartbeats = 0
        switch message {
        case .hello:
            break
        case .state(let state):
            self.state = state
            clock.ingest(state)
            isConnecting = false
            errorMessage = nil
        case .error(let error):
            errorMessage = error.message
            isConnecting = false
        case .close:
            clearSession()
        case .ping:
            session?.enqueue(.pong)
        case .pong:
            break
        case .launch, .control:
            break
        }
    }

    private func startHeartbeat(connectionId: UUID) {
        heartbeatTask?.cancel()
        missedHeartbeats = 0
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard let self, self.connectionId == connectionId else { return }
                self.missedHeartbeats += 1
                if self.missedHeartbeats > Self.maxMissedHeartbeats {
                    self.beginReconnect(reason: "Lost connection to the TV.")
                    return
                }
                self.session?.enqueue(.ping)
            }
        }
    }

    private func beginReconnect(reason: String) {
        guard let target = lastTarget else { clearSession(); return }
        heartbeatTask?.cancel(); heartbeatTask = nil
        readTask?.cancel(); readTask = nil
        let old = session
        session = nil
        connectionId = nil
        if old != nil { Task { await old?.close() } }
        isReconnecting = true
        errorMessage = nil
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for attempt in 1...Self.maxReconnectAttempts {
                try? await Task.sleep(for: .seconds(Double(attempt)))   // backoff 1,2,3,4,5s
                if Task.isCancelled { return }
                if await self.connect(to: target, isReconnectAttempt: true) {
                    self.isReconnecting = false
                    return
                }
            }
            self.isReconnecting = false
            self.errorMessage = reason
            self.clearSession()
        }
    }

    private func fail(_ message: String, connectionId: UUID?) {
        guard connectionId == nil || self.connectionId == connectionId else { return }
        errorMessage = message
        isConnecting = false
        session = nil
        readTask?.cancel()
        readTask = nil
        self.connectionId = nil
    }

    private func clearSession() {
        readTask?.cancel()
        readTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        missedHeartbeats = 0
        isReconnecting = false
        lastTarget = nil
        session = nil
        connectionId = nil
        activeTarget = nil
        state = nil
        isConnecting = false
        isShowingRemoteControl = false
    }

    private func closeCurrentSession(sendClose: Bool) async {
        readTask?.cancel()
        readTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        missedHeartbeats = 0
        if let session {
            if sendClose {
                try? await session.send(.close)
            }
            await session.close()
        }
        session = nil
        connectionId = nil
        state = nil
        activeTarget = nil
    }

    private func makeHello() -> SiloCastMessage {
        let device = AppleDeviceIdentity.current
        let server = ServerRegistry.shared.activeServer
        return .hello(SiloCastHello(
            role: .phone,
            deviceName: device.name,
            deviceId: device.id,
            serverId: server?.id,
            serverName: server?.displayName,
            supportedVersions: [SiloCastProtocol.version]
        ))
    }
}
#endif
