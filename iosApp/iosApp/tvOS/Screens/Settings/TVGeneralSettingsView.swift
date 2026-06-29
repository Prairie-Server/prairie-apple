#if os(tvOS)
import SwiftUI

/// General sub-screen of tvOS Settings, presented as a full-screen cover
/// from the root menu (push navigation inside the tab's `Form` is unreliable
/// on tvOS 26 — see `TVSettingsView`).
///
/// Home for app-level preferences that aren't playback or subtitles. Today
/// that's the opt-in Audiobooks tab, and it's the natural place any future
/// top-menu / header customization would live.
struct TVGeneralSettingsView: View {
    @State private var navPrefs = TVNavPreferences.shared

    var body: some View {
        NavigationStack {
            Form {
                navigationSection
            }
            .navigationTitle("General")
            .background(Color.continuumBackground.ignoresSafeArea())
        }
    }

    // MARK: - Sections

    private var navigationSection: some View {
        Section {
            // Bound straight to the local store (not the settings view model):
            // this is a device-local, per-profile preference, not one of the
            // server-synced device settings the view model owns.
            Toggle(isOn: Binding(
                get: { navPrefs.showAudiobooks },
                set: { navPrefs.setShowAudiobooks($0) }
            )) {
                FocusAwareRowLabel(title: "Show Audiobooks")
            }
        } header: {
            Text("Top Menu")
        } footer: {
            Text("Adds an Audiobooks tab to the top menu when your server has an audiobook library. Hidden by default.")
        }
    }
}
#endif
