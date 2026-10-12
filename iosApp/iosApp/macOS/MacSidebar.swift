#if os(macOS)
import SwiftUI

/// The Mac's grouped sidebar: Home, then collapsible Libraries, Discover, and
/// Your Stuff groups. Group expansion is remembered per device.
struct MacSidebar: View {
    let sections: [MacSidebarSection]
    /// Row matching the page in view; nil when the page belongs to no row.
    let highlight: MainTabDestinationID?
    let onSelect: (MainTabDestinationID) -> Void

    @Environment(AppRouter.self) private var router
    /// Shared session cache, so the avatar never flashes its fallback.
    private let profileStore = CurrentProfileStore.shared

    @AppStorage("mac.sidebar.librariesExpanded") private var librariesExpanded = true
    @AppStorage("mac.sidebar.discoverExpanded") private var discoverExpanded = true
    @AppStorage("mac.sidebar.yourStuffExpanded") private var yourStuffExpanded = true

    var body: some View {
        List(selection: Binding<MainTabDestinationID?>(
            get: { highlight },
            set: { value in
                guard let value else { return }
                onSelect(value)
            }
        )) {
            ForEach(sections) { section in
                if let title = section.title {
                    Section(isExpanded: expansion(for: section.id)) {
                        rows(for: section)
                    } header: {
                        Text(title)
                            .font(.prairieCaption)
                            .textCase(.uppercase)
                            .tracking(PrairieTheme.macSidebarHeadingTracking)
                    }
                } else {
                    rows(for: section)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollBounceBehavior(.basedOnSize)
        .scrollContentBackground(.hidden)
        .background(Color.prairieSidebarCanvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            PrairieWordmarkView(width: PrairieTheme.macSidebarWordmarkWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PrairieTheme.padding)
                .padding(.vertical, PrairieTheme.spacing)
                // Opaque, so rows scrolling underneath do not show through.
                .background(Color.prairieSidebarCanvas)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ProfileAvatarMenu(
                profile: profileStore.profile,
                showsName: true,
                onOpenSettings: { router.navigate(to: .settings) },
                onOpenRequests: { router.navigate(to: .requestsHub) },
                onSwitchProfile: { router.switchProfile() },
                onSwitchServer: { router.navigate(to: .serverList) },
                onSignOut: { router.signOutAndReset() }
            )
            .menuIndicator(.hidden)
            .padding(.horizontal, PrairieTheme.padding)
            .padding(.vertical, PrairieTheme.smallPadding)
            .background(Color.prairieSidebarCanvas)
            .overlay(alignment: .top) {
                Divider().overlay(Color.prairieDivider)
            }
            .task { await profileStore.refresh() }
        }
    }

    private func rows(for section: MacSidebarSection) -> some View {
        ForEach(section.items) { destination in
            let isSelected = highlight == destination.id
            HStack {
                Label(
                    destination.title,
                    systemImage: isSelected ? destination.selectedIcon : destination.icon
                )
                if destination.id == .app(.search) {
                    Spacer()
                    Text("⌘K")
                        .font(.prairieSmall)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(destination.id)
        }
    }

    private func expansion(for id: MacSidebarSectionID) -> Binding<Bool> {
        switch id {
        case .home: return .constant(true)
        case .libraries: return $librariesExpanded
        case .discover: return $discoverExpanded
        case .yourStuff: return $yourStuffExpanded
        }
    }
}
#endif
