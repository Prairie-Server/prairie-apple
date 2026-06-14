#if os(iOS)
import SwiftUI

/// Modal flow after the user taps "Set up" on a discovered TV: connect, pick
/// servers, confirm the match code, watch progress.
struct TVPairingView: View {
    let tv: DiscoveredTV
    var onClose: () -> Void

    @State private var coordinator: CompanionPairingCoordinator?
    @State private var selection: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator?.state ?? .connecting {
                case .connecting:
                    ProgressView("Connecting to \(tv.name)…")
                case let .pickServers(_, servers):
                    serverPicker(servers)
                case let .confirmMatch(_, serverName, matchCode):
                    confirm(serverName: serverName, matchCode: matchCode)
                case let .working(progress):
                    ProgressView(progress)
                case let .finished(signedIn, failed):
                    finished(signedIn: signedIn, failed: failed)
                case let .error(message):
                    errorState(message)
                }
            }
            .navigationTitle("Set up Apple TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } } }
        }
        .task {
            let session = PairingSession(endpoint: tv.endpoint)
            let stream = await session.open()
            let coordinator = CompanionPairingCoordinator(session: session, stream: stream)
            self.coordinator = coordinator
            await coordinator.begin()
        }
        .onDisappear { Task { await coordinator?.cancel() } }
    }

    @ViewBuilder private func serverPicker(_ servers: [ServerEntry]) -> some View {
        List {
            Section("Which servers should this TV use?") {
                ForEach(servers) { server in
                    Button {
                        if selection.contains(server.id) { selection.remove(server.id) } else { selection.insert(server.id) }
                    } label: {
                        HStack {
                            Text(server.displayName)
                            Spacer()
                            if selection.contains(server.id) { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Button("Continue") {
                let chosen = servers.filter { selection.contains($0.id) }
                Task { await coordinator?.pushSelected(chosen) }
            }
            .disabled(selection.isEmpty)
        }
    }

    @ViewBuilder private func confirm(serverName: String, matchCode: String) -> some View {
        VStack(spacing: 24) {
            Text("Does your Apple TV show this code?").font(.headline)
            Text(matchCode).font(.system(size: 44, weight: .heavy, design: .rounded)).textCase(.uppercase)
            Text("For \(serverName)").foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Doesn’t match") { Task { await coordinator?.declineMatch() } }
                    .buttonStyle(.bordered)
                Button("Yes, set up") { Task { await coordinator?.confirmMatch() } }
                    .buttonStyle(.borderedProminent)
            }
        }.padding()
    }

    @ViewBuilder private func finished(signedIn: [String], failed: [String]) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            Text(signedIn.isEmpty ? "Nothing set up" : "Set up \(signedIn.joined(separator: ", "))").font(.headline)
            if !failed.isEmpty { Text("Couldn’t set up: \(failed.joined(separator: ", "))").foregroundStyle(.secondary) }
            Button("Done") { close() }.buttonStyle(.borderedProminent)
        }.padding()
    }

    @ViewBuilder private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.yellow)
            Text(message).multilineTextAlignment(.center)
            Button("Close") { close() }.buttonStyle(.borderedProminent)
        }.padding()
    }

    private func close() {
        Task { await coordinator?.cancel(); onClose() }
    }
}
#endif
