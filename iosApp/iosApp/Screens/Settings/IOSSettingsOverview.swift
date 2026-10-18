#if os(iOS)
import SwiftUI

/// Searchable iOS Settings overview in the system Settings idiom: an
/// inset-grouped list of one-line rows with graphite icon tiles. Search
/// still matches each row's longer description, which VoiceOver reads as
/// the row's hint.
struct IOSSettingsOverview: View {
    let viewModel: SettingsViewModel
    let diagnosticsModel: DiagnosticsViewModel
    let uiCustomization: UICustomizationPreferences
    @Binding var showSignOutConfirm: Bool

    @Environment(AppRouter.self) private var router
    @State private var navPrefs = AppNavPreferences.shared
    @State private var launchPreferences = ProfileLaunchPreferences.shared
    @State private var experimental = ExperimentalFeatures.shared
    @State private var searchText = ""
    @State private var showsSignInTV = false
    @State private var accountSignIn = AccountSignInModel.live()

    var body: some View {
        List {
            Section {
                SettingsAccountCard(
                    avatar: viewModel.activeProfile?.avatarEmoji,
                    avatarImageUrl: viewModel.activeProfile?.avatarImageUrl,
                    name: viewModel.displayName,
                    subtitle: viewModel.accountSubtitleLine,
                    isAdministrator: viewModel.userInfo?.isAdmin == true,
                    action: switchProfile
                )
            }

            SettingsSearchField(text: $searchText)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if hasSearchResults {
                // Prairie: Quick Connect sits near the top (PR #22 / #24).
                if matchesQuickConnect {
                    quickConnectSection
                }

                preferencesSection
                playbackSection

                if diagnosticsModel.shouldShowSettings && matchesDiagnostics {
                    diagnosticsSection
                }

                if matchesAccountSignIn {
                    accountSignInSection
                }

                if matchesConnectionSection {
                    connectionSection
                }

                if matchesExperimentalSection {
                    experimentalSection
                }

                if matchesAboutSection {
                    aboutSection
                }

                if matchesSignOut {
                    signOutSection
                }
            } else {
                ContentUnavailableView.search
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .listRowBackground(Color.clear)
            }
        }
        .prairieGroupedListStyle()
        .prairieScrollContentBackgroundHidden()
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(Color.prairieBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .prairieNavigationTitleDisplayMode(.large)
        .prairieToolbarColorSchemeDark()
        .onAppear(perform: navPrefs.refresh)
        .task { await accountSignIn.load() }
        .sheet(isPresented: $showsSignInTV) {
            SignInTVView(onSwitchAccount: { server, link, choosingAccount in
                showsSignInTV = false
                router.switchAccount(forTVApproval: link, on: server, choosingAccount: choosingAccount)
            }, onClose: { showsSignInTV = false })
        }
    }

    @ViewBuilder
    private var preferencesSection: some View {
        if matchesGeneral || matchesInterface {
            Section("Preferences") {
                if matchesGeneral {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        SettingsOverviewRow(
                            title: "General",
                            subtitle: "Profile selection and app startup",
                            systemImage: "gearshape.fill",
                            value: launchPreferences.behavior.title
                        )
                    }
                }

                if matchesInterface {
                    NavigationLink {
                        InterfaceCustomizationView()
                    } label: {
                        SettingsOverviewRow(
                            title: "Interface",
                            subtitle: "Navigation, cards, and poster presentation",
                            systemImage: "rectangle.3.group.fill",
                            value: uiCustomization.cardPresentation.preset?.title ?? "Custom"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var playbackSection: some View {
        if matchesPlaybackSection {
            Section("Playback") {
                if matchesPlayback {
                    NavigationLink {
                        PlaybackSettingsView(viewModel: viewModel)
                    } label: {
                        SettingsOverviewRow(
                            title: "Playback",
                            subtitle: "Quality, language, and episode behavior",
                            systemImage: "play.fill",
                            value: viewModel.preferredQualityLabel
                        )
                    }
                }

                if matchesSubtitles {
                    NavigationLink {
                        SubtitleSettingsView(viewModel: viewModel)
                    } label: {
                        SettingsOverviewRow(
                            title: "Subtitles",
                            subtitle: "Language, behavior, and appearance",
                            systemImage: "captions.bubble.fill",
                            value: viewModel.subtitleLanguageName
                        )
                    }
                }

                if matchesDownloads {
                    NavigationLink {
                        DownloadsSettingsView()
                    } label: {
                        SettingsOverviewRow(
                            title: "Downloads",
                            subtitle: "Quality, cleanup, and storage",
                            systemImage: "arrow.down.circle.fill"
                        )
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("Support") {
            NavigationLink {
                DiagnosticsSettingsView(
                    model: diagnosticsModel,
                    profile: viewModel.activeProfile
                )
            } label: {
                SettingsOverviewRow(
                    title: "Diagnostics",
                    subtitle: "Capture, review, and send support reports",
                    systemImage: "stethoscope",
                    value: diagnosticsModel.featureState.title
                )
            }
        }
    }

    /// Prairie: approve a sign-in code shown on a TV, Roku, Smart TV or the
    /// web login screen (`QuickConnectView`).
    private var quickConnectSection: some View {
        Section {
            NavigationLink {
                QuickConnectView()
            } label: {
                SettingsOverviewRow(
                    title: "Quick Connect",
                    subtitle: "Sign in another device with its on-screen code",
                    systemImage: "qrcode.viewfinder"
                )
            }
            .accessibilityIdentifier("settings-quick-connect")
        }
    }

    /// Shown only when the server has an external sign-in provider or the
    /// account already has a provider identity.
    private var accountSignInSection: some View {
        Section("Account") {
            NavigationLink {
                AccountSignInView(model: accountSignIn)
            } label: {
                SettingsOverviewRow(
                    title: "Sign-in",
                    subtitle: "Connect or disconnect your sign-in provider",
                    systemImage: "person.badge.key.fill",
                    value: accountSignIn.identities.first?.providerName
                )
            }
            .accessibilityIdentifier("settings.accountSignIn")
        }
    }

    private var matchesAccountSignIn: Bool {
        accountSignIn.showsEntry && matches("sign-in", "sign in", "account", "provider", "sso", "single sign-on", "connect")
    }

    private var connectionSection: some View {
        Section("Connection") {
            Button {
                router.navigate(to: .serverList)
            } label: {
                SettingsOverviewRow(
                    title: "Server",
                    subtitle: "Manage this device's Prairie connection",
                    systemImage: "server.rack",
                    value: viewModel.serverDisplayName,
                    showsChevron: true
                )
            }
            if matchesSignInTV {
                Button {
                    showsSignInTV = true
                } label: {
                    SettingsOverviewRow(
                        title: "Sign in a TV",
                        subtitle: "Approve a TV's sign-in code with this account",
                        systemImage: "tv",
                        showsChevron: true
                    )
                }
            }
        }
    }

    private var matchesSignInTV: Bool {
        matches("sign in a tv", "tv", "apple tv", "android tv", "code", "device")
    }

    private var aboutSection: some View {
        Section("About") {
            SettingsOverviewRow(
                title: "Version",
                subtitle: "Installed Prairie app version",
                systemImage: "info.circle.fill",
                value: SettingsViewModel.versionString
            )

            // Prairie: update check against the Prairie release feed (PR #18).
            SettingsOverviewRow(
                title: "Update Status",
                subtitle: "Compares this build with the latest Prairie release",
                systemImage: "arrow.triangle.2.circlepath",
                value: viewModel.appUpdateStatus.statusLabel
            )
            .accessibilityIdentifier("settings-update-status")

            if let latest = viewModel.appUpdateStatus.latestVersionLabel {
                SettingsOverviewRow(
                    title: "Latest Version",
                    subtitle: "Newest published Prairie release",
                    systemImage: "tag.fill",
                    value: latest
                )
            }

            if let changelogURL = viewModel.appUpdateStatus.changelogURL {
                Link(destination: changelogURL) {
                    SettingsOverviewRow(
                        title: "Changelog",
                        subtitle: "What changed in recent Prairie releases",
                        systemImage: "doc.text.fill",
                        showsChevron: true
                    )
                }
            }

            if let releaseURL = viewModel.appUpdateStatus.releaseURL {
                Link(destination: releaseURL) {
                    SettingsOverviewRow(
                        title: "View Update",
                        subtitle: "Open the newer Prairie release",
                        systemImage: "arrow.down.app.fill",
                        showsChevron: true
                    )
                }
            }

            Link(destination: PrairieLegalLinks.privacyPolicy) {
                SettingsOverviewRow(
                    title: "Privacy Policy",
                    subtitle: "Learn how Prairie handles your information",
                    systemImage: "hand.raised.fill",
                    showsChevron: true
                )
            }

            NavigationLink {
                AcknowledgementsView()
            } label: {
                SettingsOverviewRow(
                    title: "Acknowledgements",
                    subtitle: "Services Prairie uses, and open source licenses",
                    systemImage: "curlybraces"
                )
            }

            Link(destination: PrairieLegalLinks.sourceCode) {
                SettingsOverviewRow(
                    title: "Source Code",
                    subtitle: "Get Prairie's source code under the AGPL",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    showsChevron: true
                )
            }
        }
    }

    private var experimentalSection: some View {
        // A query naming the section shows every row; otherwise each row
        // appears only for its own terms.
        Section("Extra Features") {
            if matchesExperimentalName || matchesAudiobooks {
                SettingsOverviewToggleRow(
                    title: "Show Audiobooks",
                    subtitle: "Add Audiobooks to the main navigation",
                    systemImage: "book.closed.fill",
                    isOn: Binding(
                        get: { navPrefs.showAudiobooks },
                        set: { navPrefs.setShowAudiobooks($0) }
                    )
                )
            }

            ForEach(ExperimentalFeature.allCases.filter {
                matchesExperimentalName || matches($0.title, $0.subtitle)
            }, id: \.self) { feature in
                SettingsOverviewToggleRow(
                    title: feature.title,
                    subtitle: feature.subtitle,
                    systemImage: feature.systemImage,
                    isOn: Binding(
                        get: { experimental.isEnabled(feature) },
                        set: { feature.setEnabled($0) }
                    )
                )
            }
        }
    }

    private var signOutSection: some View {
        Section {
            Button("Sign Out", role: .destructive) {
                showSignOutConfirm = true
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color.red)
        }
    }

    private func switchProfile() {
        router.switchProfile()
    }

    private var matchesPlayback: Bool {
        matches("playback", "quality", "resolution", "bitrate", "cellular", "mobile data", "audio", "dolby vision", "episodes", "skipping", "skip interval", "rewind", "fast forward", "audiobooks", "spoilers", "blur", "thumbnails", "descriptions")
    }

    private var matchesInterface: Bool {
        matches("interface", "appearance", "navigation", "menu", "cards", "posters", "captions")
    }

    private var matchesGeneral: Bool {
        matches("general", "profile", "selection", "launch", "startup", "automatic", "every time", "hours", "who's watching", "pin")
    }

    private var matchesSubtitles: Bool {
        matches("subtitles", "captions", "language", "behavior", "appearance")
    }

    private var matchesDownloads: Bool {
        DownloadManager.shared.downloadsEnabled
            && matches("downloads", "offline", "quality", "cleanup", "storage")
    }

    private var matchesDiagnostics: Bool {
        matches("diagnostics", "support", "reports", "debug", "crash")
    }

    private var matchesAudiobooks: Bool {
        matches("audiobooks", "navigation", "library")
    }

    private var matchesConnectionSection: Bool {
        matches("server", "connection", viewModel.serverDisplayName) || matchesSignInTV
    }

    private var matchesAboutSection: Bool {
        matches(
            "about",
            "version",
            SettingsViewModel.versionString,
            "update",
            "changelog",
            "release",
            "privacy",
            "policy",
            "information",
            "open source",
            "licenses",
            "acknowledgements",
            "source code",
            "AGPL",
            "credits",
            "attribution",
            "TMDB"
        )
    }

    private var matchesQuickConnect: Bool {
        matches("quick connect", "code", "sign in", "device", "tv", "pair")
    }

    private var matchesExperimentalName: Bool {
        matches("extra features", "experimental")
    }

    private var matchesExperimentalSection: Bool {
        matchesExperimentalName
            || matchesAudiobooks
            || ExperimentalFeature.allCases.contains { matches($0.title, $0.subtitle) }
    }

    private var matchesSignOut: Bool {
        matches("sign out", "account")
    }

    private var matchesPlaybackSection: Bool {
        matchesPlayback || matchesSubtitles || matchesDownloads
    }

    private var hasSearchResults: Bool {
        matchesQuickConnect
            || matchesGeneral
            || matchesInterface
            || matchesPlaybackSection
            || (diagnosticsModel.shouldShowSettings && matchesDiagnostics)
            || matchesAccountSignIn
            || matchesConnectionSection
            || matchesExperimentalSection
            || matchesAboutSection
            || matchesSignOut
    }

    private func matches(_ terms: String...) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return terms.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
#endif
