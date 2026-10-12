#if os(macOS)
import SwiftUI

extension Notification.Name {
    /// Posted by the app menu's "Settings…" item. The signed-in shell opens
    /// Settings; on the sign-in and profile screens nothing listens.
    static let prairieOpenSettings = Notification.Name("prairieOpenSettings")
    /// Posted by the View menu's "Search" item.
    static let prairieOpenSearch = Notification.Name("prairieOpenSearch")
}

/// The standard "Settings…" item in the app menu, with its ⌘, shortcut.
struct MacSettingsCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NotificationCenter.default.post(name: .prairieOpenSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        // A menu command, so the shortcut works with the sidebar hidden.
        CommandGroup(after: .sidebar) {
            Button("Search") {
                NotificationCenter.default.post(name: .prairieOpenSearch, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
        }
    }
}
#endif
