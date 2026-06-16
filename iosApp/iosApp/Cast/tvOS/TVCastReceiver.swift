#if os(tvOS)
import Foundation
import Network
import OSLog

@MainActor
@Observable
final class TVCastReceiver {
    static let shared = TVCastReceiver()

    private var listener: NWListener?
    private var advertisedServerId: String?
    private weak var router: AppRouter?
    private var activeSession: SiloCastSession?
    private var activeConnectionId: UUID?
    private(set) var standbyState: TVCastStandbyState?
    private var readTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var authWatchdogTask: Task<Void, Never>?
    private var missedHeartbeats = 0
    private var isAuthorized = false
    private static let heartbeatInterval: Duration = .seconds(3)
    private static let maxMissedHeartbeats = 3      // ~9–12s of silence ⇒ dead
    private static let authGracePeriod: Duration = .seconds(5)
    private weak var playerViewModel: PlayerViewModel?
    private var playerContentId: String?
    private var remoteControllerName: String?
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.continuum.app",
        category: "cast.receiver"
    )

    private init() {}

    func start(router: AppRouter) {
        self.router = router
        guard let server = ServerRegistry.shared.activeServer else {
            stop()
            return
        }
        if listener != nil, advertisedServerId == server.id {
            return
        }

        stop()

        let device = AppleDeviceIdentity.current
        let txt = NWTXTRecord([
            "v": String(SiloCastProtocol.version),
            "name": device.name,
            "id": device.id,
            "server": server.id,
            "serverName": server.displayName
        ])

        do {
            let listener = try NWListener(using: SiloCastSession.tlsParameters())
            listener.service = NWListener.Service(
                name: device.name,
                type: SiloCastProtocol.serviceType,
                txtRecord: txt
            )
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    await self?.accept(connection)
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    Self.logger.error("cast listener failed: \(String(describing: error), privacy: .public)")
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            advertisedServerId = server.id
        } catch {
            Self.logger.error("failed to start cast listener: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        advertisedServerId = nil
        closeActiveSession(sendClose: false)
    }

    func disconnectRemoteControl() {
        closeActiveSession(sendClose: true)
    }

    func registerPlayer(_ viewModel: PlayerViewModel, contentId: String) {
        playerViewModel = viewModel
        playerContentId = contentId
        standbyState = nil
        startStateUpdates()
        sendState()
    }

    func unregisterPlayer(_ viewModel: PlayerViewModel) {
        guard playerViewModel === viewModel else { return }
        playerViewModel = nil
        playerContentId = nil
        stateTask?.cancel()
        stateTask = nil
        refreshStandbyState()
        sendState()
    }

    private func accept(_ connection: NWConnection) async {
        if activeSession != nil {
            // Newest controller wins (matches AirPlay/Cast); frees the old slot.
            closeActiveSession(sendClose: true)
        }

        let session = SiloCastSession(connection: connection)
        let connectionId = UUID()
        activeSession = session
        activeConnectionId = connectionId
        isAuthorized = false
        remoteControllerName = nil
        refreshStandbyState()
        let stream = await session.open()
        startReadLoop(stream: stream, connectionId: connectionId)
        if playerViewModel != nil {
            startStateUpdates()
        }
        startHeartbeat(connectionId: connectionId)
        startAuthWatchdog(connectionId: connectionId)

        do {
            try await session.send(makeHello())
            sendState()
        } catch {
            closeActiveSession(sendClose: false)
        }
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
                    self?.sendError(code: "connection_failed", message: error.localizedDescription)
                    self?.handleConnectionClosed(connectionId: connectionId)
                }
            }
        }
    }

    private func handle(_ message: SiloCastMessage, connectionId: UUID) {
        guard activeConnectionId == connectionId else { return }
        missedHeartbeats = 0
        switch message {
        case .hello(let hello):
            guard let serverId = hello.serverId, !serverId.isEmpty,
                  let activeServerId = ServerRegistry.shared.activeServerId,
                  serverId == activeServerId else {
                sendError(code: "server_mismatch",
                          message: "This Apple TV is connected to a different Silo server.")
                closeActiveSession(sendClose: true)
                return
            }
            isAuthorized = true
            authWatchdogTask?.cancel(); authWatchdogTask = nil
            remoteControllerName = hello.deviceName
            refreshStandbyState()
        case .launch(let launch):
            guard isAuthorized else {
                sendError(code: "unauthorized", message: "Connect with a matching Silo account first.")
                return
            }
            handleLaunch(launch)
        case .control(let command):
            guard isAuthorized else {
                sendError(code: "unauthorized", message: "Connect with a matching Silo account first.")
                return
            }
            handleControl(command)
        case .ping:
            activeSession?.enqueue(.pong)
        case .pong, .state, .error:
            break
        case .close:
            closeActiveSession(sendClose: false)
        }
    }

    private func handleLaunch(_ launch: SiloCastLaunchRequest) {
        guard launch.serverId == ServerRegistry.shared.activeServerId else {
            sendError(code: "server_mismatch", message: "This Apple TV is connected to a different Silo server.")
            return
        }

        let playback = launch.playback
        standbyState = nil
        router?.presentPlayer(
            contentId: playback.contentId,
            fileId: playback.fileId,
            audioTrackIndex: playback.audioTrackIndex,
            subtitleTrackIndex: playback.subtitleTrackIndex,
            startFromBeginning: playback.startFromBeginning,
            resumePosition: playback.resumePosition
        )
        sendLoadingState(for: playback.contentId)
    }

    private func handleControl(_ command: SiloCastControlCommand) {
        if command.name == .stop {
            stopRemotePlayback()
            return
        }

        guard let playerViewModel else {
            sendError(code: "player_not_ready", message: "The TV player is not ready yet.")
            return
        }

        do {
            try playerViewModel.applySiloCastControl(command)
            sendState()
        } catch {
            sendError(code: "command_failed", message: error.localizedDescription)
        }
    }

    private func handleConnectionClosed(connectionId: UUID) {
        guard activeConnectionId == connectionId else { return }
        activeSession = nil
        activeConnectionId = nil
        remoteControllerName = nil
        readTask = nil
        stateTask?.cancel()
        stateTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        authWatchdogTask?.cancel(); authWatchdogTask = nil
        missedHeartbeats = 0
        isAuthorized = false
        standbyState = nil
    }

    private func closeActiveSession(sendClose: Bool) {
        let session = activeSession
        if sendClose, let session {
            Task { try? await session.send(.close) }
        }
        if let session {
            Task { await session.close() }
        }
        activeSession = nil
        activeConnectionId = nil
        remoteControllerName = nil
        readTask?.cancel()
        readTask = nil
        stateTask?.cancel()
        stateTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        authWatchdogTask?.cancel(); authWatchdogTask = nil
        missedHeartbeats = 0
        isAuthorized = false
        standbyState = nil
    }

    private func stopRemotePlayback() {
        playerViewModel = nil
        playerContentId = nil
        stateTask?.cancel()
        stateTask = nil
        router?.presentedPlayer = nil
        refreshStandbyState()
        sendState()
    }

    private func refreshStandbyState() {
        guard activeSession != nil, playerViewModel == nil else {
            standbyState = nil
            return
        }
        standbyState = TVCastStandbyState(
            controllerName: remoteControllerName,
            serverName: ServerRegistry.shared.activeServer?.displayName
        )
    }

    private func startHeartbeat(connectionId: UUID) {
        heartbeatTask?.cancel()
        missedHeartbeats = 0
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard let self, self.activeConnectionId == connectionId else { return }
                self.missedHeartbeats += 1
                if self.missedHeartbeats > Self.maxMissedHeartbeats {
                    Self.logger.info("cast: controller heartbeat timed out; closing session")
                    self.closeActiveSession(sendClose: false)
                    return
                }
                self.activeSession?.enqueue(.ping)
            }
        }
    }

    private func startAuthWatchdog(connectionId: UUID) {
        authWatchdogTask?.cancel()
        authWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.authGracePeriod)
            guard let self, self.activeConnectionId == connectionId, !self.isAuthorized else { return }
            Self.logger.info("cast: controller never authorized; closing session")
            self.closeActiveSession(sendClose: true)
        }
    }

    private func startStateUpdates() {
        stateTask?.cancel()
        guard activeSession != nil else { return }
        stateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.sendState()
            }
        }
    }

    private func sendState() {
        guard let session = activeSession else { return }
        let state: SiloCastPlaybackState
        if let playerViewModel {
            state = playerViewModel.makeSiloCastPlaybackState(contentId: playerContentId)
        } else {
            state = idleState()
        }
        session.enqueue(.state(state))
    }

    private func sendLoadingState(for contentId: String) {
        guard let session = activeSession else { return }
        let state = SiloCastPlaybackState(
            contentId: contentId,
            sessionId: nil,
            title: "Loading",
            subtitle: nil,
            isPlaying: false,
            isLoading: true,
            isBuffering: false,
            currentTime: 0,
            duration: 0,
            audioTracks: [],
            subtitleTracks: [],
            selectedAudioTrackId: nil,
            selectedSubtitleTrackId: nil,
            qualityOptions: [],
            activeQualityId: ApplePlaybackQuality.autoId,
            isQualitySwitching: false,
            playbackSpeed: PlayerSettings.shared.playbackSpeed,
            videoGravity: PlayerSettings.shared.videoGravity.rawValue,
            hdrEnabled: PlayerSettings.shared.hdrEnabled,
            supportsVideoGravity: false,
            supportsHDRToggle: false,
            volume: 1.0,
            isMuted: false,
            hasNextEpisode: false,
            nextEpisodeTitle: nil,
            error: nil
        )
        session.enqueue(.state(state))
    }

    private func sendError(code: String, message: String) {
        guard let session = activeSession else { return }
        session.enqueue(.error(SiloCastErrorMessage(code: code, message: message)))
    }

    private func makeHello() -> SiloCastMessage {
        let device = AppleDeviceIdentity.current
        let server = ServerRegistry.shared.activeServer
        return .hello(SiloCastHello(
            role: .tv,
            deviceName: device.name,
            deviceId: device.id,
            serverId: server?.id,
            serverName: server?.displayName,
            supportedVersions: [SiloCastProtocol.version]
        ))
    }

    private func idleState() -> SiloCastPlaybackState {
        SiloCastPlaybackState(
            contentId: nil,
            sessionId: nil,
            title: "Ready",
            subtitle: nil,
            isPlaying: false,
            isLoading: false,
            isBuffering: false,
            currentTime: 0,
            duration: 0,
            audioTracks: [],
            subtitleTracks: [],
            selectedAudioTrackId: nil,
            selectedSubtitleTrackId: nil,
            qualityOptions: [],
            activeQualityId: ApplePlaybackQuality.autoId,
            isQualitySwitching: false,
            playbackSpeed: PlayerSettings.shared.playbackSpeed,
            videoGravity: PlayerSettings.shared.videoGravity.rawValue,
            hdrEnabled: PlayerSettings.shared.hdrEnabled,
            supportsVideoGravity: false,
            supportsHDRToggle: false,
            volume: 1.0,
            isMuted: false,
            hasNextEpisode: false,
            nextEpisodeTitle: nil,
            error: nil
        )
    }
}
#endif
