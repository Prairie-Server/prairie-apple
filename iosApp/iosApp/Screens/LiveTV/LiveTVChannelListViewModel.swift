import Foundation

/// Loads the Live TV channel list and attaches now/next guide slots.
@MainActor
@Observable
final class LiveTVChannelListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(ErrorState)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var channels: [LiveTVChannel] = []
    private(set) var nowNextByChannel: [String: LiveTVNowNext] = [:]
    private(set) var recordingMessage: String?

    private let api: ContinuumAPI

    init(api: ContinuumAPI = .shared) {
        self.api = api
    }

    /// Test/preview seam for empty and loading smoke coverage.
    static func preview(state: LoadState, channels: [LiveTVChannel] = []) -> LiveTVChannelListViewModel {
        let vm = LiveTVChannelListViewModel(api: .shared)
        vm.loadState = state
        vm.channels = channels
        return vm
    }

    var isLoading: Bool { loadState == .loading }
    var isEmpty: Bool { loadState == .loaded && channels.isEmpty }
    var error: ErrorState? {
        if case .failed(let state) = loadState { return state }
        return nil
    }

    func load() async {
        loadState = .loading
        recordingMessage = nil
        do {
            let all = try await api.liveTVChannels()
            channels = all.filter(\.enabled).sorted {
                ($0.displayNumber, $0.displayName) < ($1.displayNumber, $1.displayName)
            }
            loadState = .loaded
            await refreshGuide()
        } catch {
            loadState = .failed(ErrorState(error))
        }
    }

    func refreshGuide() async {
        guard !channels.isEmpty else {
            nowNextByChannel = [:]
            return
        }
        let now = Date()
        let start = now.addingTimeInterval(-30 * 60)
        let end = now.addingTimeInterval(6 * 60 * 60)
        do {
            let guide = try await api.liveTVGuide(
                channelIds: channels.map(\.id),
                start: start,
                end: end
            )
            nowNextByChannel = Self.nowNextMap(programs: guide.programs, at: now)
        } catch {
            // Guide is best-effort; channel list remains usable without it.
        }
    }

    /// Pure helper: for each channel, pick the program spanning `at` and the
    /// soonest program that starts after it.
    nonisolated static func nowNextMap(
        programs: [LiveTVProgram],
        at date: Date
    ) -> [String: LiveTVNowNext] {
        var byChannel: [String: [LiveTVProgram]] = [:]
        for program in programs {
            byChannel[program.channelId, default: []].append(program)
        }
        var result: [String: LiveTVNowNext] = [:]
        for (channelId, list) in byChannel {
            let sorted = list.sorted { $0.start < $1.start }
            let now = sorted.first { $0.start <= date && date < $0.stop }
            let next: LiveTVProgram?
            if let now {
                next = sorted.first { $0.start >= now.stop }
            } else {
                next = sorted.first { $0.start > date }
            }
            result[channelId] = LiveTVNowNext(now: now, next: next)
        }
        return result
    }

    func startSession(for channel: LiveTVChannel) async throws -> LiveTVSessionStartResponse {
        try await api.startLiveTVSession(channelId: channel.id)
    }

    /// Best-effort tuner release when a started session never reaches the player.
    func releaseSession(_ sessionId: String) async {
        try? await api.releaseLiveTVSession(sessionId: sessionId)
    }

    func scheduleRecording(program: LiveTVProgram) async {
        recordingMessage = nil
        do {
            let input = LiveTVScheduleRecordingInput(
                programId: program.id,
                channelId: program.channelId,
                start: program.start,
                stop: program.stop,
                title: program.displayTitle
            )
            _ = try await api.scheduleLiveTVRecording(input)
            recordingMessage = "Recording scheduled"
        } catch {
            recordingMessage = error.localizedDescription
        }
    }

    func setStatusMessage(_ message: String?) {
        recordingMessage = message
    }
}
