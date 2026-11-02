#if os(iOS)
import SwiftUI

struct PrairieControlTargetPickerView: View {
    let request: PrairieControlPlaybackRequest?
    let controller: PrairieControlClient

    @State private var browser = PrairieControlBrowser()
    @State private var searchTimedOut = false
    /// Read once: the picker lives for one search.
    @State private var rememberedRoku = PrairieControlClient.rememberedRoku
    private let pairingKeys = PrairieControlPairingKeys()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if !displayedTargets.isEmpty {
                    foundList
                } else if searchTimedOut {
                    emptyState
                } else {
                    searchingState
                }
            }
            .prairieSheetBackground()
            .statusColumnSheetWidth()
            .navigationTitle("Remote Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .task {
                browser.start()
                try? await Task.sleep(for: .seconds(8))
                searchTimedOut = true
            }
            .onDisappear { browser.stop() }
        }
        .preferredColorScheme(.dark)
        .presentationDetents(displayedTargets.count > 3 ? [.medium, .large] : [.medium])
    }

    private var searchingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching for Prairie TVs…")
                .font(.headline)
                .foregroundStyle(Color.prairieSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Prairie TVs Found",
            systemImage: "tv",
            description: Text(missingRokuHint
                ?? "TVs on this server appear here while Prairie is open on them. On a Roku, open Prairie with the Roku remote.")
        )
    }

    /// The phone can't open Prairie on a Roku, so when the Roku it last
    /// controlled hasn't turned up by the end of the search, the picker says
    /// how to bring it back.
    private var missingRokuHint: String? {
        guard searchTimedOut, let roku = rememberedRoku, !browser.found.contains(where: { $0.id == roku.id }) else { return nil }
        return "Don't see \(roku.name)? Open Prairie on your Roku."
    }

    private var foundList: some View {
        List(displayedTargets) { target in
            Button {
                Task {
                    if let request {
                        await controller.play(on: target, request: request)
                    } else {
                        await controller.connect(to: target)
                    }
                    dismiss()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv")
                        .font(.title3)
                        .foregroundStyle(Color.prairieOnSurface)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.prairieChromeRestingFill))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.name).font(.headline)
                        if target.transport == .sealed, pairingKeys.key(for: target) == nil {
                            Text("Scan this Roku's pairing code to connect")
                                .font(.subheadline)
                                .foregroundStyle(Color.prairieSecondaryText)
                        } else if request != nil, target.protocolVersion < 2 {
                            Text("Update Prairie on this TV to use your profile")
                                .font(.subheadline)
                                .foregroundStyle(Color.prairieSecondaryText)
                        } else if target.isPlaying {
                            Text("Playing now")
                                .font(.subheadline)
                                .foregroundStyle(Color.prairiePrimary)
                        } else if let serverName = target.serverName {
                            Text(target.targetsActiveServer
                                 ? serverName
                                 : "Will temporarily use your server")
                                .font(.subheadline)
                                .foregroundStyle(Color.prairieSecondaryText)
                        }
                    }

                    Spacer()

                    if controller.isConnecting && controller.activeTarget?.id == target.id {
                        ProgressView().accessibilityLabel("Connecting")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(request != nil && target.protocolVersion < 2)
            .listRowBackground(Color.prairieSurface)
        }
        .safeAreaInset(edge: .bottom) {
            if let missingRokuHint {
                Text(missingRokuHint)
                    .font(.footnote)
                    .foregroundStyle(Color.prairieSecondaryText)
                    .padding(.bottom, 12)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var displayedTargets: [PrairieControlTarget] {
        guard request == nil else { return browser.found }
        guard ServerRegistry.shared.activeServer != nil else { return [] }
        return browser.found.filter(\.targetsActiveServer)
    }
}

#if DEBUG
#Preview("Searching") {
    PrairieControlTargetPickerView(request: nil, controller: PrairieControlClient())
}
#endif
#endif
