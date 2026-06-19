import SwiftUI

/// The shared right-hand action cluster used at the top of tab-root screens:
/// Search and a profile-avatar menu with Settings / Switch Profile / Sign Out.
///
/// Each tab renders its own leading content (e.g. library selector on the
/// Libraries tab, a static title on Home) and places this view on the
/// trailing side of a single `HStack` row.
struct TabTopBarActions: View {
    let profile: UserProfile?
    let onSearch: () -> Void
    let onOpenSettings: () -> Void
    let onSwitchProfile: () -> Void
    let onSwitchServer: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        glassCluster {
            HStack(spacing: 4) {
                TopBarIconButton(systemImage: "magnifyingglass", accessibilityLabel: "Search", action: onSearch)
                ProfileAvatarMenu(
                    profile: profile,
                    onOpenSettings: onOpenSettings,
                    onSwitchProfile: onSwitchProfile,
                    onSwitchServer: onSwitchServer,
                    onSignOut: onSignOut
                )
            }
        }
    }

    /// Wraps the search/profile pair in a `GlassEffectContainer` so their
    /// individual glass capsules blend into one another. Falls back to a
    /// plain container where the API is unavailable (macOS < 26).
    @ViewBuilder
    private func glassCluster<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(macOS)
        if #available(macOS 26, *) {
            GlassEffectContainer { content() }
        } else {
            content()
        }
        #else
        GlassEffectContainer { content() }
        #endif
    }
}

/// Circular icon button used for Search actions in the top bar.
private struct TopBarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.continuumOnSurface)
                .frame(width: 40, height: 40)
                .siloGlass(in: .circle)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Profile avatar rendered via `ProfileAvatarView` (which handles DiceBear
/// presets, URLs, emojis, and initials uniformly). Wraps a Menu exposing
/// Settings / Switch Profile / Sign Out so the user can reach app settings
/// and manage their account without leaving the current tab.
private struct ProfileAvatarMenu: View {
    let profile: UserProfile?
    let onOpenSettings: () -> Void
    let onSwitchProfile: () -> Void
    let onSwitchServer: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        Menu {
            Button {
                onOpenSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Divider()

            Button {
                onSwitchProfile()
            } label: {
                Label("Switch Profile", systemImage: "person.2")
            }
            Button {
                onSwitchServer()
            } label: {
                Label("Switch Server", systemImage: "server.rack")
            }
            Button(role: .destructive) {
                onSignOut()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            ProfileAvatarView(
                avatar: profile?.avatarEmoji,
                name: profile?.name ?? "",
                size: 36
            )
        }
        .menuStyle(.borderlessButton)
    }
}
