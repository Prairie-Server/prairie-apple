import SwiftUI
import AVKit

private enum LiveTVTab: String, CaseIterable, Identifiable {
    case guide
    case channels
    case recordings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guide: return "Guide"
        case .channels: return "Channels"
        case .recordings: return "My recordings"
        }
    }
}

/// Live TV tab: guide grid, channel lineup, and recordings.
struct LiveTVChannelListView: View {
    @State private var viewModel: LiveTVChannelListViewModel
    @State private var selectedTab: LiveTVTab = .guide
    @State private var channelFilter = ""
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
                Button("Cancel recording", systemImage: "xmark.circle", role: .destructive) {
                    Task { await viewModel.cancelRecording(recording) }
                    recordingPendingCancel = nil
                }
                Button("Keep", systemImage: "checkmark", role: .cancel) {
                    recordingPendingCancel = nil
                }
            } message: { recording in
                Text(recording.title)
            }
            #if os(tvOS)
            .onAppear { applyFocusRequest(focusRequest) }
            .onChange(of: focusRequest) { _, request in applyFocusRequest(request) }
            .onChange(of: selectedTab) { _, _ in applyFocusRequest(focusRequest) }
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
            VStack(spacing: 0) {
                tabSelector
                tabContent
            }
        }
    }

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LiveTVTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: ContinuumTheme.normalDuration)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.title)
                            if tab == .recordings, !viewModel.scheduledRecordings.isEmpty {
                                Text("\(viewModel.scheduledRecordings.count)")
                                    .font(.continuumCaption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.continuumSurfaceElevated)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.continuumCaption)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundColor(selectedTab == tab ? Color.continuumBackground : .continuumSecondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? Color.continuumOnSurface : Color.continuumSurfaceElevated)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("livetv-tab-\(tab.rawValue)")
                }
            }
            .padding(.horizontal, ContinuumTheme.padding)
            .padding(.vertical, ContinuumTheme.smallPadding)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .guide:
            guideTab
        case .channels:
            channelsTab
        case .recordings:
            recordingsTab
        }
    }

    private var guideTab: some View {
        List {
            ForEach(viewModel.channels) { channel in
                guideChannelSection(channel)
                    #if os(tvOS)
                    .listRowBackground(Color.clear)
                    #else
                    .listRowBackground(Color.continuumSurface)
                    #endif
            }
        }
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .accessibilityIdentifier("livetv-guide")
    }

    @ViewBuilder
    private func guideChannelSection(_ channel: LiveTVChannel) -> some View {
        Section {
            let programs = viewModel.programs(for: channel.id)
            if programs.isEmpty {
                Text("No guide data")
                    .font(.continuumCaption)
                    .foregroundStyle(Color.continuumSecondaryText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(programs) { program in
                            guideProgramCard(program)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(channel.displayNumber)
                    .font(.continuumHeadline)
                Text(channel.displayName)
                    .font(.continuumBody)
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
        }
    }

    private func guideProgramCard(_ program: LiveTVProgram) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(program.displayTitle)
                .font(.continuumCaption)
                .foregroundStyle(Color.continuumOnSurface)
                .lineLimit(2)
            Text(timeRange(program))
                .font(.continuumCaption)
                .foregroundStyle(Color.continuumSecondaryText)
            if !program.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await viewModel.scheduleRecording(program: program) }
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .font(.continuumCaption)
                }
                .disabled(viewModel.isRecordingBusy)
                #if !os(tvOS)
                .buttonStyle(.bordered)
                #endif
            }
        }
        .frame(width: 160, alignment: .leading)
        .padding(10)
        .background(Color.continuumSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var channelsTab: some View {
        List {
            #if !os(tvOS)
            Section {
                TextField("Filter channels…", text: $channelFilter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            #endif
            Section("Channels") {
                ForEach(filteredChannels) { channel in
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

    private var filteredChannels: [LiveTVChannel] {
        let query = channelFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.channels }
        return viewModel.channels.filter { channel in
            let haystack = "\(channel.displayNumber) \(channel.callsign) \(channel.name)".lowercased()
            return haystack.contains(query)
        }
    }

    private var recordingsTab: some View {
        List {
            recordingsSection(
                title: "Scheduled & in progress",
                emptyMessage: "Nothing scheduled yet. Pick a programme from the guide or channel list.",
                recordings: viewModel.scheduledRecordings
            )
            recordingsSection(
                title: "History",
                emptyMessage: "Completed and failed recordings will show up here.",
                recordings: viewModel.historyRecordings
            )
        }
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .accessibilityIdentifier("livetv-recordings")
    }

    @ViewBuilder
    private func recordingsSection(
        title: String,
        emptyMessage: String,
        recordings: [LiveTVRecording]
    ) -> some View {
        Section(title) {
            if recordings.isEmpty {
                Text(emptyMessage)
                    .font(.continuumCaption)
                    .foregroundStyle(Color.continuumSecondaryText)
            } else {
                ForEach(recordings) { recording in
                    recordingRow(recording)
                        #if os(tvOS)
                        .listRowBackground(Color.clear)
                        #else
                        .listRowBackground(Color.continuumSurface)
                        #endif
                }
            }
        }
    }

    @ViewBuilder
    private func recordingRow(_ recording: LiveTVRecording) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .font(.continuumBody)
                    .foregroundStyle(Color.continuumOnSurface)
                let channelLabel = viewModel.channel(for: recording.channelId)?.displayName
                    ?? recording.channelId
                Text("\(recording.status.capitalized) · \(channelLabel) · \(recordingTimeRange(recording))")
                    .font(.continuumCaption)
                    .foregroundStyle(Color.continuumSecondaryText)
            }
            Spacer(minLength: 8)
            if let contentId = playableLibraryItemId(from: recording) {
                Button {
                    router.presentPlayer(contentId: contentId)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                #if !os(tvOS)
                .buttonStyle(.borderedProminent)
                .tint(Color.continuumAccent)
                #endif
            } else if recording.status.lowercased() == "scheduled"
                || recording.status.lowercased() == "pending" {
                let normalizedId = recording.id.trimmingCharacters(in: .whitespacesAndNewlines)
                Button(role: .destructive) {
                    recordingPendingCancel = recording
                } label: {
                    if viewModel.cancellingRecordingIds.contains(normalizedId) {
                        ProgressView()
                    } else {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }
                .disabled(viewModel.cancellingRecordingIds.contains(normalizedId))
                #if !os(tvOS)
                .buttonStyle(.bordered)
                #endif
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("livetv-recording-\(recording.id)")
    }

    private func playableLibraryItemId(from recording: LiveTVRecording) -> String? {
        guard recording.status.lowercased() == "completed" else { return nil }
        let id = recording.libraryItemId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return id.isEmpty ? nil : id
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
                       channel.id == filteredChannels.first?.id {
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
            let raw = session.playableURLString
            guard !raw.isEmpty else {
                await viewModel.releaseSession(session.sessionId)
                viewModel.setStatusMessage("Live stream URL missing")
                return
            }

            let serverUrl = await ContinuumAPI.shared.currentServerUrl()
            let resolved = LiveTVURLResolver.resolve(raw, serverBaseURL: serverUrl)
            if session.isHLS, resolved == nil {
                await viewModel.releaseSession(session.sessionId)
                viewModel.setStatusMessage("Live stream URL missing")
                return
            }

            router.presentLivePlayer(
                sessionId: session.sessionId,
                streamURL: resolved,
                title: channel.displayName,
                isHLS: session.isHLS
            )

            if let note = session.note?.trimmingCharacters(in: .whitespacesAndNewlines),
               !note.isEmpty {
                viewModel.setStatusMessage(note)
            }
        } catch {
            viewModel.setStatusMessage(error.localizedDescription)
        }
    }

    #if os(tvOS)
    private static let placeholderFocusId = "__livetv-placeholder__"

    private func applyFocusRequest(_ request: Int) {
        guard request > 0 else { return }
        let focusChannels = selectedTab == .channels ? filteredChannels : viewModel.channels
        if let first = focusChannels.first?.id {
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
