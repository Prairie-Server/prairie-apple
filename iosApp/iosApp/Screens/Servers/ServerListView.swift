import SwiftUI

/// Picker + management UI for the set of saved Silo servers.
///
/// Shared between iOS and tvOS with minor platform-specific tweaks:
/// - iOS: Navigation `List` with swipe-to-delete and long-press rename.
/// - tvOS: focus-aware tile row; rename via an on-screen alert.
///
/// Switching a server asks the `AppRouter` to re-evaluate auth state so
/// the user lands on login or profile-select for the new server (or on
/// home if tokens are still valid there).
struct ServerListView: View {
    @Environment(AppRouter.self) private var router
    @State private var registry = ServerRegistry.shared
    @State private var renameTarget: ServerEntry?
    @State private var renameInput: String = ""
    @State private var removeTarget: ServerEntry?

    var body: some View {
        contentList
            .navigationTitle("Servers")
            #if !os(tvOS)
            .continuumNavigationTitleDisplayMode(.inline)
            #endif
            .continuumBackground()
            .continuumScrollContentBackgroundHidden()
            .alert(
                "Rename server",
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                ),
                presenting: renameTarget
            ) { entry in
                #if !os(tvOS)
                TextField("Name", text: $renameInput)
                #endif
                Button("Save") {
                    registry.rename(serverId: entry.id, userOverrideName: renameInput)
                    renameTarget = nil
                }
                if entry.userOverrideName != nil {
                    Button("Reset to server-provided name", role: .destructive) {
                        registry.rename(serverId: entry.id, userOverrideName: nil)
                        renameTarget = nil
                    }
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            } message: { _ in
                Text("Override the server-provided name with a label just for this device.")
            }
            .alert(
                "Remove this server?",
                isPresented: Binding(
                    get: { removeTarget != nil },
                    set: { if !$0 { removeTarget = nil } }
                ),
                presenting: removeTarget
            ) { entry in
                Button("Remove", role: .destructive) {
                    let wasActive = entry.id == registry.activeServerId
                    Task {
                        await registry.remove(serverId: entry.id)
                        await MainActor.run {
                            removeTarget = nil
                            // Removing the active server leaves the app
                            // pointed at a fallback (or none). Re-enter
                            // the auth state machine so the user lands
                            // in the right place instead of on a stale
                            // main-app screen.
                            if wasActive { refreshAuthState() }
                        }
                    }
                }
                Button("Cancel", role: .cancel) { removeTarget = nil }
            } message: { entry in
                Text("Sign-in credentials for \(entry.displayName) will be forgotten on this device.")
            }
    }

    private var contentList: some View {
        List {
            Section {
                ForEach(registry.sortedEntries) { entry in
                    row(for: entry)
                }
            } header: {
                Text("Saved servers")
                    .foregroundColor(.continuumSecondaryText)
            }
            .listRowBackground(Color.continuumSurfaceElevated)

            Section {
                Button {
                    router.resetToServerSetup()
                } label: {
                    Label("Add Server", systemImage: "plus")
                        .foregroundColor(.continuumOnSurface)
                }
            }
            .listRowBackground(Color.continuumSurfaceElevated)
        }
        .continuumGroupedListStyle()
    }

    @ViewBuilder
    private func row(for entry: ServerEntry) -> some View {
        Button {
            switchTo(entry)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.id == registry.activeServerId
                      ? "checkmark.circle.fill"
                      : "server.rack")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.continuumOnSurface)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.continuumSubheadline)
                        .foregroundColor(.continuumOnSurface)
                        .lineLimit(1)
                    Text(entry.url)
                        .font(.continuumCaption)
                        .foregroundColor(.continuumSecondaryText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameInput = entry.userOverrideName ?? entry.fetchedName ?? ""
                renameTarget = entry
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                removeTarget = entry
            } label: {
                Label("Remove Server", systemImage: "trash")
            }
        }
        #if !os(tvOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                removeTarget = entry
            } label: {
                Label("Remove", systemImage: "trash")
            }
            Button {
                renameInput = entry.userOverrideName ?? entry.fetchedName ?? ""
                renameTarget = entry
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.continuumOnSurface)
        }
        #endif
    }

    private func switchTo(_ entry: ServerEntry) {
        guard entry.id != registry.activeServerId else {
            // Already active: re-evaluate in case tokens expired and
            // the UI just needs to catch up.
            refreshAuthState()
            return
        }
        Task {
            await registry.switchTo(serverId: entry.id)
            await MainActor.run { refreshAuthState() }
        }
    }

    /// Recompute auth state for the (possibly new) active server and
    /// drop any in-tab navigation that belonged to the previous server.
    private func refreshAuthState() {
        router.popToRoot()
        let auth = AuthService.shared
        if !auth.hasServer {
            router.authState = .needsServerSetup
        } else if !auth.isLoggedIn {
            router.authState = .needsLogin
        } else if !auth.hasProfile {
            router.authState = .needsProfile
        } else {
            router.authState = .authenticated
        }
    }
}
