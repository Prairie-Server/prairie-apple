import Foundation

enum PrairieControlProtocol {
    static let version = 2
    static let supportedVersions = [1, 2]
    static let serviceType = "_prairiecast._tcp"

    static func negotiatedVersion(with peer: [Int]) -> Int? {
        supportedVersions.filter(peer.contains).max()
    }
}

enum PrairieControlPeerRole: String, Codable, Equatable, Sendable {
    case phone
    case tv
}

struct PrairieControlHello: Codable, Equatable, Sendable {
    let role: PrairieControlPeerRole
    let deviceName: String
    let deviceId: String
    let serverId: String?
    let serverName: String?
    let supportedVersions: [Int]
}

struct PrairieControlPlaybackRequest: Codable, Equatable, Sendable {
    let contentId: String
    let fileId: Int?
    let audioTrackIndex: Int?
    let subtitleTrackIndex: Int?
    let startFromBeginning: Bool
    let resumePosition: Double?
}

struct PrairieControlLaunchRequest: Codable, Equatable, Sendable {
    let serverId: String
    let playback: PrairieControlPlaybackRequest
}

struct PrairieControlHandoffOffer: Codable, Equatable, Sendable {
    let requestId: String
    let serverId: String
    let serverURL: String
    let serverName: String?
    let profileId: String
    /// Display-only label for the verified profile ID. Older peers omit it.
    let profileName: String?
}

struct PrairieControlHandoffChallenge: Codable, Equatable, Sendable {
    let requestId: String
    let userCode: String
    let matchCode: String
    let expiresAt: String
}

struct PrairieControlHandoffReady: Codable, Equatable, Sendable {
    let requestId: String
    let serverId: String
    let profileId: String
    let sessionExpiresAt: String
    let reused: Bool
}

struct PrairieControlHandoffCancel: Codable, Equatable, Sendable {
    let requestId: String
    let reason: String
    let message: String?
}

struct PrairieControlTrack: Codable, Equatable, Identifiable, Sendable {
    let kind: String
    let trackId: Int64
    let title: String
    let detail: String?

    var id: String { "\(kind)-\(trackId)" }
}

struct PrairieControlOption: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let detail: String?
}

struct PrairieControlPlaybackState: Codable, Equatable, Sendable {
    let contentId: String?
    let sessionId: String?
    let title: String
    let subtitle: String?
    let isPlaying: Bool
    let isLoading: Bool
    let isBuffering: Bool
    let currentTime: Double
    let duration: Double
    let audioTracks: [PrairieControlTrack]
    let subtitleTracks: [PrairieControlTrack]
    let selectedAudioTrackId: Int64?
    let selectedSubtitleTrackId: Int64?
    let qualityOptions: [PrairieControlOption]
    let activeQualityId: String
    let isQualitySwitching: Bool
    let playbackSpeed: Double
    let videoGravity: String
    let hdrEnabled: Bool
    let supportsVideoGravity: Bool
    let supportsHDRToggle: Bool
    var subtitleSyncMs: Int? = nil
    var subtitlePosition: String? = nil
    var supportsSubtitleDelay: Bool? = nil
    var supportsSubtitlePosition: Bool? = nil
    let volume: Double
    let isMuted: Bool
    let hasNextEpisode: Bool
    let nextEpisodeTitle: String?
    let error: String?
}

struct PrairieControlCommand: Codable, Equatable, Sendable {
    enum Name: String, Codable, Sendable {
        case play
        case pause
        case playPause = "play_pause"
        case seek
        case stop
        case selectAudioTrack = "select_audio_track"
        case selectSubtitleTrack = "select_subtitle_track"
        case setPlaybackSpeed = "set_playback_speed"
        case setQuality = "set_quality"
        case setVideoGravity = "set_video_gravity"
        case setHDREnabled = "set_hdr_enabled"
        case setSubtitleSyncMs = "set_subtitle_sync_ms"
        case setSubtitlePosition = "set_subtitle_position"
        case setVolume = "set_volume"
        case setMuted = "set_muted"
        case playNext = "play_next"
    }

    let name: Name
    let seconds: Double?
    let trackId: Int64?
    let speed: Double?
    let volume: Double?
    let value: String?
    let enabled: Bool?
    let milliseconds: Int?

    init(
        name: Name,
        seconds: Double? = nil,
        trackId: Int64? = nil,
        speed: Double? = nil,
        volume: Double? = nil,
        value: String? = nil,
        enabled: Bool? = nil,
        milliseconds: Int? = nil
    ) {
        self.name = name
        self.seconds = seconds
        self.trackId = trackId
        self.speed = speed
        self.volume = volume
        self.value = value
        self.enabled = enabled
        self.milliseconds = milliseconds
    }

    static let play = PrairieControlCommand(name: .play)
    static let pause = PrairieControlCommand(name: .pause)
    static let playPause = PrairieControlCommand(name: .playPause)
    static let stop = PrairieControlCommand(name: .stop)

    static func seek(seconds: Double) -> PrairieControlCommand {
        PrairieControlCommand(name: .seek, seconds: seconds)
    }

    static func selectAudioTrack(_ trackId: Int64) -> PrairieControlCommand {
        PrairieControlCommand(name: .selectAudioTrack, trackId: trackId)
    }

    static func selectSubtitleTrack(_ trackId: Int64?) -> PrairieControlCommand {
        PrairieControlCommand(name: .selectSubtitleTrack, trackId: trackId)
    }

    static func setPlaybackSpeed(_ speed: Double) -> PrairieControlCommand {
        PrairieControlCommand(name: .setPlaybackSpeed, speed: speed)
    }

    static func setQuality(_ qualityId: String) -> PrairieControlCommand {
        PrairieControlCommand(name: .setQuality, value: qualityId)
    }

    static func setVideoGravity(_ value: String) -> PrairieControlCommand {
        PrairieControlCommand(name: .setVideoGravity, value: value)
    }

    static func setHDREnabled(_ enabled: Bool) -> PrairieControlCommand {
        PrairieControlCommand(name: .setHDREnabled, enabled: enabled)
    }

    static func setSubtitleSyncMs(_ milliseconds: Int) -> PrairieControlCommand {
        PrairieControlCommand(name: .setSubtitleSyncMs, milliseconds: milliseconds)
    }

    static func setSubtitlePosition(_ value: String) -> PrairieControlCommand {
        PrairieControlCommand(name: .setSubtitlePosition, value: value)
    }

    static let playNext = PrairieControlCommand(name: .playNext)

    static func setVolume(_ volume: Double) -> PrairieControlCommand {
        PrairieControlCommand(name: .setVolume, volume: volume)
    }

    static func setMuted(_ muted: Bool) -> PrairieControlCommand {
        PrairieControlCommand(name: .setMuted, enabled: muted)
    }
}

struct PrairieControlErrorMessage: Codable, Equatable, Sendable {
    let code: String
    let message: String
}

enum PrairieControlMessage: Equatable, Sendable {
    case hello(PrairieControlHello)
    case handoffOffer(PrairieControlHandoffOffer)
    case handoffChallenge(PrairieControlHandoffChallenge)
    case handoffReady(PrairieControlHandoffReady)
    case handoffCancel(PrairieControlHandoffCancel)
    case launch(PrairieControlLaunchRequest)
    case control(PrairieControlCommand)
    case state(PrairieControlPlaybackState)
    case error(PrairieControlErrorMessage)
    case ping
    case pong
    case close
}

extension PrairieControlMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, v
        case hello, launch, control, state, error
        case handoffOffer, handoffChallenge, handoffReady, handoffCancel
    }

    private enum Kind: String, Codable {
        case hello
        case handoffOffer = "handoff_offer"
        case handoffChallenge = "handoff_challenge"
        case handoffReady = "handoff_ready"
        case handoffCancel = "handoff_cancel"
        case launch
        case control
        case state
        case error
        case ping
        case pong
        case close
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(PrairieControlProtocol.version, forKey: .v)
        switch self {
        case .hello(let hello):
            try c.encode(Kind.hello, forKey: .type)
            try c.encode(hello, forKey: .hello)
        case .handoffOffer(let offer):
            try c.encode(Kind.handoffOffer, forKey: .type)
            try c.encode(offer, forKey: .handoffOffer)
        case .handoffChallenge(let challenge):
            try c.encode(Kind.handoffChallenge, forKey: .type)
            try c.encode(challenge, forKey: .handoffChallenge)
        case .handoffReady(let ready):
            try c.encode(Kind.handoffReady, forKey: .type)
            try c.encode(ready, forKey: .handoffReady)
        case .handoffCancel(let cancel):
            try c.encode(Kind.handoffCancel, forKey: .type)
            try c.encode(cancel, forKey: .handoffCancel)
        case .launch(let launch):
            try c.encode(Kind.launch, forKey: .type)
            try c.encode(launch, forKey: .launch)
        case .control(let control):
            try c.encode(Kind.control, forKey: .type)
            try c.encode(control, forKey: .control)
        case .state(let state):
            try c.encode(Kind.state, forKey: .type)
            try c.encode(state, forKey: .state)
        case .error(let error):
            try c.encode(Kind.error, forKey: .type)
            try c.encode(error, forKey: .error)
        case .ping:
            try c.encode(Kind.ping, forKey: .type)
        case .pong:
            try c.encode(Kind.pong, forKey: .type)
        case .close:
            try c.encode(Kind.close, forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .hello:
            self = .hello(try c.decode(PrairieControlHello.self, forKey: .hello))
        case .handoffOffer:
            self = .handoffOffer(try c.decode(PrairieControlHandoffOffer.self, forKey: .handoffOffer))
        case .handoffChallenge:
            self = .handoffChallenge(try c.decode(PrairieControlHandoffChallenge.self, forKey: .handoffChallenge))
        case .handoffReady:
            self = .handoffReady(try c.decode(PrairieControlHandoffReady.self, forKey: .handoffReady))
        case .handoffCancel:
            self = .handoffCancel(try c.decode(PrairieControlHandoffCancel.self, forKey: .handoffCancel))
        case .launch:
            self = .launch(try c.decode(PrairieControlLaunchRequest.self, forKey: .launch))
        case .control:
            self = .control(try c.decode(PrairieControlCommand.self, forKey: .control))
        case .state:
            self = .state(try c.decode(PrairieControlPlaybackState.self, forKey: .state))
        case .error:
            self = .error(try c.decode(PrairieControlErrorMessage.self, forKey: .error))
        case .ping:
            self = .ping
        case .pong:
            self = .pong
        case .close:
            self = .close
        }
    }
}
