#if os(tvOS)
import Foundation
import Network
import OSLog

@MainActor
@Observable
final class TVControlReceiver {
    static let shared = TVControlReceiver()

    private var listener: NWListener?
    private var advertisedServerId: String?
    /// Bumped whenever we intentionally cancel/replace the listener, so its
    /// state handler can tell a system-initiated failure (restart) from our
    /// own teardown (ignore).
    private var listenerGeneration = 0
    /// Mirrors "is a player registered" into the Bonjour TXT record so phones
    /// can see that this TV is playing *before* connecting. A bare connection
    /// with no player takes over the TV screen (standby view), so the phone's
    /// silent auto-reconnect must only target TVs that are actually playing.
    private var isPlaybackAdvertised = false
    private weak var router: AppRouter?
    private var activeSession: SiloControlSession?
    private var activeConnectionId: UUID?
    private(set) var standbyState: TVControlStandbyState?
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
        category: "control.receiver"
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
        startListener(server: server)
    }

    private func startListener(server: ServerEntry) {
        listenerGeneration += 1
        let generation = listenerGeneration

        let device = AppleDeviceIdentity.current
        let txt = NWTXTRecord([
            "v": String(SiloControlProtocol.version),
            "name": device.name,
            "id": device.id,
            "server": server.id,
            "serverName": server.displayName,
            "playing": isPlaybackAdvertised ? "1" : "0"
        ])

        do {
            let listener = try NWListener(using: SiloControlSession.tlsParameters())
            listener.service = NWListener.Service(
                name: device.name,
                type: SiloControlProtocol.serviceType,
                txtRecord: txt
            )
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    await self?.accept(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.listenerGeneration == generation else { return }
                    switch state {
                    case .failed(let error):
                        Self.logger.error("control listener failed: \(String(describing: error), privacy: .public)")
                        self.scheduleListenerRestart()
                    case .cancelled:
                        // We bump the generation before cancelling ourselves, so a
                        // current-generation cancel is the system tearing us down
                        // (e.g. after suspension) — recover the advertisement.
                        self.scheduleListenerRestart()
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            advertisedServerId = server.id
        } catch {
            Self.logger.error("failed to start control listener: \(String(describing: error), privacy: .public)")
        }
    }

    private func scheduleListenerRestart() {
        listener = nil
        advertisedServerId = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.listener == nil, let router = self.router else { return }
            self.start(router: router)
        }
    }

    /// Rebuilds the Bonjour advertisement with an updated `playing` TXT flag.
    /// Recreating the listener does not disturb the accepted control session.
    private func setPlaybackAdvertised(_ playing: Bool) {
        guard isPlaybackAdvertised != playing else { return }
        isPlaybackAdvertised = playing
        guard listener != nil, let server = ServerRegistry.shared.activeServer,
              advertisedServerId == server.id else { return }
        listenerGeneration += 1
        listener?.cancel()
        listener = nil
        startListener(server: server)
    }

    func stop() {
        listenerGeneration += 1
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
        setPlaybackAdvertised(true)
    }

    func unregisterPlayer(_ viewModel: PlayerViewModel) {
        guard playerViewModel === viewModel else { return }
        playerViewModel = nil
        playerContentId = nil
        stateTask?.cancel()
        stateTask = nil
        refreshStandbyState()
        sendState()
        setPlaybackAdvertised(false)
    }

    private func accept(_ connection: NWConnection) async {
        if activeSession != nil {
            // Newest controller wins (matches AirPlay/Cast); frees the old slot.
            closeActiveSession(sendClose: true)
        }

        let session = SiloControlSession(connection: connection)
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
        stream: AsyncThrowingStream<SiloControlMessage, Error>,
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

    private func handle(_ message: SiloControlMessage, connectionId: UUID) {
        guard activeConnectionId == connectionId else { return }
        // NOTE: liveness is reset only on `.pong` (below), not on every inbound
        // message. A `.pong` is the controller's reply to our ping, so it's the
        // only message that proves the controller can still *receive* from us.
        // Resetting on any inbound (e.g. the controller's own pings) would let a
        // half-open connection — controller's receive path dead but its send
        // path alive — keep the session pinned open forever.
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
        case .pong:
            missedHeartbeats = 0
        case .state, .error:
            break
        case .close:
            closeActiveSession(sendClose: false)
        }
    }

    private func handleLaunch(_ launch: SiloControlLaunchRequest) {
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

    private func handleControl(_ command: SiloControlCommand) {
        if command.name == .stop {
            stopRemotePlayback()
            return
        }

        // Volume, mute, and next-episode all flow through applySiloControlCommand
        // below; only .stop needs special handling (it dismisses the player).
        guard let playerViewModel else {
            sendError(code: "player_not_ready", message: "The TV player is not ready yet.")
            return
        }

        do {
            try playerViewModel.applySiloControlCommand(command)
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
        let read = readTask
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

        guard let session else {
            read?.cancel()
            return
        }
        // Send the goodbye BEFORE cancelling the read task. Cancelling the
        // consumer fires the message stream's onTermination, which tears the
        // connection down and races ahead of the `.close` — the peer then
        // sees a bare EOF, reads it as a dropped connection, and instantly
        // auto-reconnects (the "Disconnect Remote loops right back" bug).
        // Stray inbound messages during the goodbye are dropped by the
        // activeConnectionId guard (already nil).
        Self.logger.info("control: closing session sendClose=\(sendClose, privacy: .public)")
        Task {
            if sendClose {
                await session.closeGracefully()
            } else {
                await session.close()
            }
            read?.cancel()
        }
    }

    private func stopRemotePlayback() {
        playerViewModel = nil
        playerContentId = nil
        stateTask?.cancel()
        stateTask = nil
        router?.presentedPlayer = nil
        refreshStandbyState()
        sendState()
        setPlaybackAdvertised(false)
    }

    private func refreshStandbyState() {
        guard activeSession != nil, isAuthorized, playerViewModel == nil else {
            standbyState = nil
            return
        }
        standbyState = TVControlStandbyState(
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
                    Self.logger.info("control: controller heartbeat timed out; closing session")
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
            Self.logger.info("control: controller never authorized; closing session")
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
        let state: SiloControlPlaybackState
        if let playerViewModel {
            state = playerViewModel.makeSiloControlPlaybackState(contentId: playerContentId)
        } else {
            state = idleState()
        }
        session.enqueue(.state(state))
    }

    private func sendLoadingState(for contentId: String) {
        guard let session = activeSession else { return }
        let state = SiloControlPlaybackState(
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
        session.enqueue(.error(SiloControlErrorMessage(code: code, message: message)))
    }

    private func makeHello() -> SiloControlMessage {
        let device = AppleDeviceIdentity.current
        let server = ServerRegistry.shared.activeServer
        return .hello(SiloControlHello(
            role: .tv,
            deviceName: device.name,
            deviceId: device.id,
            serverId: server?.id,
            serverName: server?.displayName,
            supportedVersions: [SiloControlProtocol.version]
        ))
    }

    private func idleState() -> SiloControlPlaybackState {
        SiloControlPlaybackState(
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
