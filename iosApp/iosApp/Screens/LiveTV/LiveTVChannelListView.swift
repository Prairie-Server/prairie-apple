import SwiftUI
import AVKit

/// Live TV tab: channel list with now/next EPG and one-tap record / play.
struct LiveTVChannelListView: View {
    @State private var viewModel: LiveTVChannelListViewModel
    @State private var startingChannelId: String?
    @Environment(AppRouter.self) private var router

    init(viewModel: LiveTVChannelListViewModel = LiveTVChannelListViewModel()) {
        _viewModel = State(initialValue: viewModel)
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
                        .foregroundStyle(.continuumOnSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.continuumSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("livetv-recording-message")
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading || viewModel.loadState == .idle {
            LoadingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("livetv-loading")
        } else if let error = viewModel.error {
            ErrorView(
                state: error,
                onRetry: { Task { await viewModel.load() } }
            )
            .accessibilityIdentifier("livetv-error")
        } else if viewModel.isEmpty {
            EmptyStateView(
                icon: "tv",
                title: "No channels yet",
                subtitle: "Ask your server admin to add an HDHomeRun tuner and scan channels"
            )
            .accessibilityIdentifier("livetv-empty")
        } else {
            channelList
        }
    }

    private var channelList: some View {
        List {
            ForEach(viewModel.channels) { channel in
                channelRow(channel)
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
        .accessibilityIdentifier("livetv-channel-list")
    }

    @ViewBuilder
    private func channelRow(_ channel: LiveTVChannel) -> some View {
        let slot = viewModel.nowNextByChannel[channel.id] ?? LiveTVNowNext()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(channel.displayNumber)
                    .font(.continuumHeadline)
                    .foregroundStyle(.continuumOnSurface)
                    .frame(minWidth: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.displayName)
                        .font(.continuumBody)
                        .foregroundStyle(.continuumOnSurface)
                    if channel.hd {
                        Text("HD")
                            .font(.continuumCaption)
                            .foregroundStyle(.continuumSecondaryText)
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
                #if !os(tvOS)
                .buttonStyle(.borderedProminent)
                .tint(.continuumAccent)
                #endif
            }

            if let now = slot.now {
                epgLine(label: "Now", program: now, allowRecord: true)
            } else {
                Text("Now — No guide data")
                    .font(.continuumCaption)
                    .foregroundStyle(.continuumSecondaryText)
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
                    .foregroundStyle(.continuumOnSurface)
                Text(timeRange(program))
                    .font(.continuumCaption)
                    .foregroundStyle(.continuumSecondaryText)
            }
            Spacer(minLength: 8)
            if allowRecord {
                Button {
                    Task { await viewModel.scheduleRecording(program: program) }
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
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
}

/// Identifiable hand-off into the live HLS player.
struct LiveTVPlayerSession: Identifiable, Hashable {
    let id = UUID()
    let sessionId: String
    let hlsURL: URL
    let title: String
}
