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

    private var session: SiloCastSession?
    private var readTask: Task<Void, Never>?
    private var connectionId: UUID?

    var hasActiveSession: Bool {
        session != nil && activeTarget != nil
    }

    @discardableResult
    func connect(to target: SiloCastTarget) async -> Bool {
        guard let activeServerId = ServerRegistry.shared.activeServerId else {
            errorMessage = "Choose a server before casting."
            return false
        }
        guard target.serverId == activeServerId else {
            errorMessage = "That TV is connected to a different server."
            return false
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
        state = nil
        isShowingRemoteControl = true

        let session = SiloCastSession(endpoint: target.endpoint)
        let connectionId = UUID()
        self.session = session
        self.connectionId = connectionId
        let stream = await session.open()
        startReadLoop(stream: stream, connectionId: connectionId)

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
        guard let session else { return }
        let connectionId = self.connectionId
        Task {
            do {
                try await session.send(.control(command))
            } catch {
                await MainActor.run {
                    if self.connectionId == connectionId {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

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
                    await MainActor.run {
                        self?.handle(message, connectionId: connectionId)
                    }
                }
                await MainActor.run {
                    self?.handleConnectionClosed(connectionId: connectionId)
                }
            } catch {
                await MainActor.run {
                    self?.fail(error.localizedDescription, connectionId: connectionId)
                }
            }
        }
    }

    private func handle(_ message: SiloCastMessage, connectionId: UUID) {
        guard self.connectionId == connectionId else { return }
        switch message {
        case .hello:
            break
        case .state(let state):
            self.state = state
            isConnecting = false
            errorMessage = nil
        case .error(let error):
            errorMessage = error.message
            isConnecting = false
        case .close:
            clearSession()
        case .launch, .control:
            break
        }
    }

    private func handleConnectionClosed(connectionId: UUID) {
        guard self.connectionId == connectionId else { return }
        session = nil
        readTask = nil
        self.connectionId = nil
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
