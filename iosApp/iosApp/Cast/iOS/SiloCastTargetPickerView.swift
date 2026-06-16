#if os(iOS)
import SwiftUI

struct SiloCastTargetPickerView: View {
    let request: SiloCastPlaybackRequest?
    @Bindable var controller: SiloCastController

    @State private var browser = SiloCastBrowser()
    @State private var searchTimedOut = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if !browser.found.isEmpty {
                    foundList
                } else if searchTimedOut {
                    emptyState
                } else {
                    searchingState
                }
            }
            .background(Color.continuumBackground.ignoresSafeArea())
            .navigationTitle("Cast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
    }

    private var searchingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching for Silo TVs…")
                .font(.headline)
                .foregroundStyle(Color.continuumSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Silo TVs Found",
            systemImage: "tv",
            description: Text("Foreground Apple TVs on this server appear here.")
        )
    }

    private var foundList: some View {
        List(browser.found) { target in
            Button {
                Task {
                    if let request {
                        await controller.cast(to: target, request: request)
                    } else {
                        await controller.connect(to: target)
                    }
                    dismiss()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv")
                        .font(.title3)
                        .foregroundStyle(Color.continuumOnSurface)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.continuumChromeRestingFill))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.name).font(.headline)
                        if let serverName = target.serverName {
                            Text(serverName)
                                .font(.subheadline)
                                .foregroundStyle(Color.continuumSecondaryText)
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
            .listRowBackground(Color.continuumSurface)
        }
        .scrollContentBackground(.hidden)
    }
}

#if DEBUG
#Preview("Searching") {
    SiloCastTargetPickerView(request: nil, controller: SiloCastController())
}
#endif
#endif
