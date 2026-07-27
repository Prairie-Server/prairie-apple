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
    private(set) var programs: [LiveTVProgram] = []
    private(set) var nowNextByChannel: [String: LiveTVNowNext] = [:]
    private(set) var recordings: [LiveTVRecording] = []
    private(set) var recordingMessage: String?
    private(set) var isRecordingBusy = false
    private(set) var cancellingRecordingIds: Set<String> = []

    private let api: ContinuumAPI
    private var schedulingProgramIds: Set<String> = []

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

    var scheduledRecordings: [LiveTVRecording] {
        recordings.filter {
            let status = $0.status.lowercased()
            return status == "scheduled" || status == "recording" || status == "pending"
        }
    }

    var historyRecordings: [LiveTVRecording] {
        recordings.filter {
            let status = $0.status.lowercased()
            return status != "scheduled"
                && status != "recording"
                && status != "pending"
                && status != "cancelled"
        }
    }

    func programs(for channelId: String, at date: Date = Date()) -> [LiveTVProgram] {
        Self.activeOrUpcomingPrograms(programs, channelId: channelId, at: date)
    }

    /// Guide rows omit programmes that have already ended (`stop <= date`).
    nonisolated static func activeOrUpcomingPrograms(
        _ programs: [LiveTVProgram],
        channelId: String,
        at date: Date
    ) -> [LiveTVProgram] {
        programs
            .filter { $0.channelId == channelId && $0.stop > date }
            .sorted { $0.start < $1.start }
    }

    func channel(for id: String) -> LiveTVChannel? {
        channels.first { $0.id == id }
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
            await refreshRecordings()
        } catch {
            loadState = .failed(ErrorState(error))
        }
    }

    func refreshRecordings() async {
        do {
            let all = try await api.liveTVRecordings()
            recordings = all
                .filter { $0.status.lowercased() != "cancelled" }
                .sorted { $0.start < $1.start }
        } catch {
            // Recordings are best-effort; channel list remains usable.
        }
    }

    func refreshGuide() async {
        guard !channels.isEmpty else {
            nowNextByChannel = [:]
            return
        }
        let now = Date()
        // Start at now — still-airing shows that began earlier are returned by overlap.
        let start = now
        let end = now.addingTimeInterval(6 * 60 * 60)
        do {
            let guide = try await api.liveTVGuide(
                channelIds: channels.map(\.id),
                start: start,
                end: end
            )
            programs = guide.programs.sorted { $0.start < $1.start }
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
        let programId = program.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !programId.isEmpty else {
            recordingMessage = "Program not found"
            return
        }
        guard program.stop > Date() else {
            recordingMessage = "Program already ended"
            return
        }
        guard !schedulingProgramIds.contains(programId) else { return }
        schedulingProgramIds.insert(programId)
        isRecordingBusy = true
        recordingMessage = nil
        defer {
            schedulingProgramIds.remove(programId)
            isRecordingBusy = !schedulingProgramIds.isEmpty
        }
        do {
            _ = try await api.scheduleLiveTVRecording(
                LiveTVScheduleRecordingInput(programId: programId)
            )
            recordingMessage = "Recording scheduled"
            await refreshRecordings()
        } catch {
            recordingMessage = ErrorState(error).message
        }
    }

    func cancelRecording(_ recording: LiveTVRecording) async {
        let id = recording.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !cancellingRecordingIds.contains(id) else { return }
        cancellingRecordingIds.insert(id)
        recordingMessage = nil
        defer { cancellingRecordingIds.remove(id) }
        do {
            try await api.cancelLiveTVRecording(id: id)
            recordingMessage = "Recording cancelled"
            await refreshRecordings()
        } catch {
            recordingMessage = ErrorState(error).message
        }
    }

    func setStatusMessage(_ message: String?) {
        recordingMessage = message
    }
}
