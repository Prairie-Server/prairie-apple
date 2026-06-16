import Foundation

enum SiloCastProtocol {
    static let version = 1
    static let serviceType = "_silocast._tcp"
}

enum SiloCastPeerRole: String, Codable, Equatable, Sendable {
    case phone
    case tv
}

struct SiloCastHello: Codable, Equatable, Sendable {
    let role: SiloCastPeerRole
    let deviceName: String
    let deviceId: String
    let serverId: String?
    let serverName: String?
    let supportedVersions: [Int]
}

struct SiloCastPlaybackRequest: Codable, Equatable, Sendable {
    let contentId: String
    let fileId: Int?
    let audioTrackIndex: Int?
    let subtitleTrackIndex: Int?
    let startFromBeginning: Bool
    let resumePosition: Double?
}

struct SiloCastLaunchRequest: Codable, Equatable, Sendable {
    let serverId: String
    let playback: SiloCastPlaybackRequest
}

struct SiloCastTrack: Codable, Equatable, Identifiable, Sendable {
    let kind: String
    let trackId: Int64
    let title: String
    let detail: String?

    var id: String { "\(kind)-\(trackId)" }
}

struct SiloCastOption: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let detail: String?
}

struct SiloCastPlaybackState: Codable, Equatable, Sendable {
    let contentId: String?
    let sessionId: String?
    let title: String
    let subtitle: String?
    let isPlaying: Bool
    let isLoading: Bool
    let isBuffering: Bool
    let currentTime: Double
    let duration: Double
    let audioTracks: [SiloCastTrack]
    let subtitleTracks: [SiloCastTrack]
    let selectedAudioTrackId: Int64?
    let selectedSubtitleTrackId: Int64?
    let qualityOptions: [SiloCastOption]
    let activeQualityId: String
    let isQualitySwitching: Bool
    let playbackSpeed: Double
    let videoGravity: String
    let hdrEnabled: Bool
    let supportsVideoGravity: Bool
    let supportsHDRToggle: Bool
    let volume: Double
    let isMuted: Bool
    let hasNextEpisode: Bool
    let nextEpisodeTitle: String?
    let error: String?
}

struct SiloCastControlCommand: Codable, Equatable, Sendable {
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

    init(
        name: Name,
        seconds: Double? = nil,
        trackId: Int64? = nil,
        speed: Double? = nil,
        volume: Double? = nil,
        value: String? = nil,
        enabled: Bool? = nil
    ) {
        self.name = name
        self.seconds = seconds
        self.trackId = trackId
        self.speed = speed
        self.volume = volume
        self.value = value
        self.enabled = enabled
    }

    static let play = SiloCastControlCommand(name: .play)
    static let pause = SiloCastControlCommand(name: .pause)
    static let playPause = SiloCastControlCommand(name: .playPause)
    static let stop = SiloCastControlCommand(name: .stop)

    static func seek(seconds: Double) -> SiloCastControlCommand {
        SiloCastControlCommand(name: .seek, seconds: seconds)
    }

    static func selectAudioTrack(_ trackId: Int64) -> SiloCastControlCommand {
        SiloCastControlCommand(name: .selectAudioTrack, trackId: trackId)
    }

    static func selectSubtitleTrack(_ trackId: Int64?) -> SiloCastControlCommand {
        SiloCastControlCommand(name: .selectSubtitleTrack, trackId: trackId)
    }

    static func setPlaybackSpeed(_ speed: Double) -> SiloCastControlCommand {
        SiloCastControlCommand(name: .setPlaybackSpeed, speed: speed)
    }

    static func setQuality(_ qualityId: String) -> SiloCastControlCommand {
        SiloCastControlCommand(name: .setQuality, value: qualityId)
    }

    static func setVideoGravity(_ value: String) -> SiloCastControlCommand {
        SiloCastControlCommand(name: .setVideoGravity, value: value)
    }

    static func setHDREnabled(_ enabled: Bool) -> SiloCastControlCommand {
        SiloCastControlCommand(name: .setHDREnabled, enabled: enabled)
    }

    static let playNext = SiloCastControlCommand(name: .playNext)

    static func setVolume(_ volume: Double) -> SiloCastControlCommand {
        SiloCastControlCommand(name: .setVolume, volume: volume)
    }

    static func setMuted(_ muted: Bool) -> SiloCastControlCommand {
        SiloCastControlCommand(name: .setMuted, enabled: muted)
    }
}

struct SiloCastErrorMessage: Codable, Equatable, Sendable {
    let code: String
    let message: String
}

enum SiloCastMessage: Equatable, Sendable {
    case hello(SiloCastHello)
    case launch(SiloCastLaunchRequest)
    case control(SiloCastControlCommand)
    case state(SiloCastPlaybackState)
    case error(SiloCastErrorMessage)
    case ping
    case pong
    case close
}

extension SiloCastMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, v
        case hello, launch, control, state, error
    }

    private enum Kind: String, Codable {
        case hello
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
        try c.encode(SiloCastProtocol.version, forKey: .v)
        switch self {
        case .hello(let hello):
            try c.encode(Kind.hello, forKey: .type)
            try c.encode(hello, forKey: .hello)
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
            self = .hello(try c.decode(SiloCastHello.self, forKey: .hello))
        case .launch:
            self = .launch(try c.decode(SiloCastLaunchRequest.self, forKey: .launch))
        case .control:
            self = .control(try c.decode(SiloCastControlCommand.self, forKey: .control))
        case .state:
            self = .state(try c.decode(SiloCastPlaybackState.self, forKey: .state))
        case .error:
            self = .error(try c.decode(SiloCastErrorMessage.self, forKey: .error))
        case .ping:
            self = .ping
        case .pong:
            self = .pong
        case .close:
            self = .close
        }
    }
}
