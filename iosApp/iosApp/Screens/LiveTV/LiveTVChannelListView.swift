import SwiftUI
import AVKit

/// Live TV tab: channel list with now/next EPG and one-tap record / play.
struct LiveTVChannelListView: View {
    @State private var viewModel: LiveTVChannelListViewModel
    @State private var startingChannelId: String?
    @State private var recordingPendingCancel: LiveTVRecording?
    @Environment(AppRouter.self) private var router

    /// Active focus hand-down token from `TVMainTabView`. When this changes
    /// (the Live TV root was selected), focus is pushed onto the first
    /// channel so the screen never opens with a dead remote.
    var focusRequest: Int = 0
    var onTopMenuFocusRequest: (() -> Void)? = nil

    #if os(tvOS)
    @FocusState private var focusedChannelId: String?
    #endif

    init(
        viewModel: LiveTVChannelListViewModel,
        focusRequest: Int = 0,
        onTopMenuFocusRequest: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.focusRequest = focusRequest
        self.onTopMenuFocusRequest = onTopMenuFocusRequest
    }

    var body: some View {
        content
            .continuumBackground()
            .navigationTitle("Live TV")
            .continuumNavigationTitleDisplayMode(.inline)
            .continuumToolbarColorSchemeDark()
            .continuumNavigationBarSurfaceBackground()
            .task {
                if viewModel.loadState == .idle {
                    await viewModel.load()
                }
            }
            #if !os(tvOS)
            .refreshable {
                await viewModel.load()
            }
            #endif
            .overlay(alignment: .bottom) {
                if let message = viewModel.recordingMessage {
                    Text(message)
                        .font(.continuumCaption)
                        .foregroundStyle(Color.continuumOnSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.continuumSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("livetv-recording-message")
                }
            }
            .confirmationDialog(
                "Cancel this recording?",
                isPresented: Binding(
                    get: { recordingPendingCancel != nil },
                    set: { if !$0 { recordingPendingCancel = nil } }
                ),
                titleVisibility: .visible,
                presenting: recordingPendingCancel
            ) { recording in
                Button("Cancel recording", role: .destructive) {
                    Task { await viewModel.cancelRecording(recording) }
                    recordingPendingCancel = nil
                }
                Button("Keep", role: .cancel) {
                    recordingPendingCancel = nil
                }
            } message: { recording in
                Text(recording.title)
            }
            #if os(tvOS)
            .onAppear { applyFocusRequest(focusRequest) }
            .onChange(of: focusRequest) { _, request in applyFocusRequest(request) }
            .onChange(of: viewModel.channels.map(\.id)) { _, _ in
                applyFocusRequest(focusRequest)
            }
            .onChange(of: viewModel.loadState) { _, _ in
                applyFocusRequest(focusRequest)
            }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading || viewModel.loadState == .idle {
            LoadingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("livetv-loading")
                #if os(tvOS)
                .focusable()
                .focused($focusedChannelId, equals: Self.placeholderFocusId)
                .onMoveCommand { direction in
                    if direction == .up { onTopMenuFocusRequest?() }
                }
                #endif
        } else if let error = viewModel.error {
            ErrorView(
                state: error,
                onRetry: { Task { await viewModel.load() } }
            )
            .accessibilityIdentifier("livetv-error")
            #if os(tvOS)
            .focusable()
            .focused($focusedChannelId, equals: Self.placeholderFocusId)
            .onMoveCommand { direction in
                if direction == .up { onTopMenuFocusRequest?() }
            }
            #endif
        } else if viewModel.isEmpty {
            EmptyStateView(
                icon: "tv",
                title: "No channels yet",
                subtitle: "Ask your server admin to add an HDHomeRun tuner and scan channels"
            )
            .accessibilityIdentifier("livetv-empty")
            #if os(tvOS)
            .focusable()
            .focused($focusedChannelId, equals: Self.placeholderFocusId)
            .onMoveCommand { direction in
                if direction == .up { onTopMenuFocusRequest?() }
            }
            #endif
        } else {
            channelList
        }
    }

    private var channelList: some View {
        List {
            if !viewModel.recordings.isEmpty {
                Section("Scheduled recordings") {
                    ForEach(viewModel.recordings) { recording in
                        recordingRow(recording)
                            #if os(tvOS)
                            .listRowBackground(Color.clear)
                            #else
                            .listRowBackground(Color.continuumSurface)
                            #endif
                    }
                }
            }
            Section("Channels") {
                ForEach(viewModel.channels) { channel in
                    channelRow(channel)
                        #if os(tvOS)
                        .listRowBackground(Color.clear)
                        #else
                        .listRowBackground(Color.continuumSurface)
                        #endif
                }
            }
        }
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .accessibilityIdentifier("livetv-channel-list")
    }

    @ViewBuilder
    private func recordingRow(_ recording: LiveTVRecording) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .font(.continuumBody)
                    .foregroundStyle(Color.continuumOnSurface)
                Text("\(recording.status.capitalized) · \(recordingTimeRange(recording))")
                    .font(.continuumCaption)
                    .foregroundStyle(Color.continuumSecondaryText)
            }
            Spacer(minLength: 8)
            if recording.status.lowercased() == "scheduled"
                || recording.status.lowercased() == "pending" {
                Button(role: .destructive) {
                    recordingPendingCancel = recording
                } label: {
                    if viewModel.cancellingRecordingIds.contains(recording.id) {
                        ProgressView()
                    } else {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }
                .disabled(viewModel.cancellingRecordingIds.contains(recording.id))
                #if !os(tvOS)
                .buttonStyle(.bordered)
                #endif
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("livetv-recording-\(recording.id)")
    }

    private func recordingTimeRange(_ recording: LiveTVRecording) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return "\(formatter.string(from: recording.start)) – \(formatter.string(from: recording.stop))"
    }

    @ViewBuilder
    private func channelRow(_ channel: LiveTVChannel) -> some View {
        let slot = viewModel.nowNextByChannel[channel.id] ?? LiveTVNowNext()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(channel.displayNumber)
                    .font(.continuumHeadline)
                    .foregroundStyle(Color.continuumOnSurface)
                    .frame(minWidth: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.displayName)
                        .font(.continuumBody)
                        .foregroundStyle(Color.continuumOnSurface)
                    if channel.hd {
                        Text("HD")
                            .font(.continuumCaption)
                            .foregroundStyle(Color.continuumSecondaryText)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    Task { await play(channel) }
                } label: {
                    if startingChannelId == channel.id {
                        ProgressView()
                    } else {
                        Label("Watch", systemImage: "play.fill")
                    }
                }
                .disabled(startingChannelId != nil)
                #if os(tvOS)
                .focused($focusedChannelId, equals: channel.id)
                .onMoveCommand { direction in
                    if direction == .up,
                       channel.id == viewModel.channels.first?.id {
                        onTopMenuFocusRequest?()
                    }
                }
                #else
                .buttonStyle(.borderedProminent)
                .tint(Color.continuumAccent)
                #endif
            }

            if let now = slot.now {
                epgLine(label: "Now", program: now, allowRecord: true)
            } else {
                Text("Now — No guide data")
                    .font(.continuumCaption)
                    .foregroundStyle(Color.continuumSecondaryText)
            }
            if let next = slot.next {
                epgLine(label: "Next", program: next, allowRecord: true)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func epgLine(label: String, program: LiveTVProgram, allowRecord: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(label) — \(program.displayTitle)")
                    .font(.continuumCaption)
                    .foregroundStyle(Color.continuumOnSurface)
                Text(timeRange(program))
                    .font(.continuumCaption)
                    .foregroundStyle(Color.continuumSecondaryText)
            }
            Spacer(minLength: 8)
            if allowRecord, !program.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await viewModel.scheduleRecording(program: program) }
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .disabled(viewModel.isRecordingBusy)
                #if !os(tvOS)
                .buttonStyle(.bordered)
                #endif
            }
        }
    }

    private func timeRange(_ program: LiveTVProgram) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: program.start)) – \(formatter.string(from: program.stop))"
    }

    private func play(_ channel: LiveTVChannel) async {
        startingChannelId = channel.id
        defer { startingChannelId = nil }
        do {
            let session = try await viewModel.startSession(for: channel)
            guard let url = URL(string: session.hlsUrl), !session.hlsUrl.isEmpty else {
                // Session was reserved but never handed to the player; free
                // the tuner so dismissal cleanup isn't required to run.
                await viewModel.releaseSession(session.sessionId)
                viewModel.setStatusMessage("Live stream URL missing")
                return
            }
            router.presentLivePlayer(
                sessionId: session.sessionId,
                hlsURL: url,
                title: channel.displayName
            )
        } catch {
            viewModel.setStatusMessage(error.localizedDescription)
        }
    }

    #if os(tvOS)
    private static let placeholderFocusId = "__livetv-placeholder__"

    private func applyFocusRequest(_ request: Int) {
        guard request > 0 else { return }
        if let first = viewModel.channels.first?.id {
            focusedChannelId = first
        } else if viewModel.isLoading
            || viewModel.loadState == .idle
            || viewModel.error != nil
            || viewModel.isEmpty {
            focusedChannelId = Self.placeholderFocusId
        }
    }
    #endif
}

/// Identifiable hand-off into the live HLS player.
struct LiveTVPlayerSession: Identifiable, Hashable {
    let id = UUID()
    let sessionId: String
    let hlsURL: URL
    let title: String
}
