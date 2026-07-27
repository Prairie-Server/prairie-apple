import SwiftUI

/// First-run / change-server picker: Saved + LAN Discovered, with manual
/// URL entry as a secondary destination (`.serverSetup`).
///
/// Shown when `authState == .needsServerSetup`. Selecting a server routes
/// to login (or restores an existing session). Phone-pairing on tvOS stays
/// inside `TVServerSetupView` via **Add manually**.
struct ConnectServerListView: View {
    var router: AppRouter

    @State private var registry = ServerRegistry.shared
    @State private var viewModel = ConnectServerListViewModel()
    #if os(tvOS)
    @FocusState private var focusedRow: FocusRow?
    #endif

    var body: some View {
        #if os(tvOS)
        tvOSBody
        #else
        phoneBody
        #endif
    }

    // MARK: - iOS / macOS

    #if !os(tvOS)
    private var phoneBody: some View {
        AuroraScreen(variant: .server, scrim: .soft, maxContentWidth: 520) {
            PrairieWordmarkView(width: 112)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 18)

            AuroraJourneyProgress(currentStep: 1)
                .frame(maxWidth: 330)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                AuroraEyebrow(text: "Connect", centered: true)
                Text("Choose a server")
                    .font(.continuumTitle)
                    .foregroundStyle(Color.auroraInk)
                    .multilineTextAlignment(.center)
                Text("Choose a saved server or one found on your LAN. Sign-in comes next.")
                    .font(.continuumBody)
                    .foregroundStyle(Color.auroraInkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            actionButtons
                .padding(.bottom, 16)

            if let status = viewModel.statusText, !status.isEmpty {
                Text(status)
                    .font(.continuumCaption)
                    .foregroundStyle(Color.auroraInkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            if let error = viewModel.errorText {
                AuroraErrorLabel(error)
                    .padding(.bottom, 8)
            }

            serverSections
        }
        .task { await viewModel.startAutoScanIfNeeded() }
        .onDisappear { viewModel.cancelScan() }
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task { await viewModel.startScan(includeDeep: true) }
            } label: {
                Text(viewModel.isScanning ? "Scanning…" : "Scan again")
            }
            .buttonStyle(AuroraPrimaryButtonStyle(isLoading: viewModel.isScanning))
            .disabled(viewModel.isScanning || viewModel.isConnecting)

            Button {
                router.navigate(to: .serverSetup)
            } label: {
                Text("Add manually")
            }
            .buttonStyle(AuroraGhostButtonStyle())
            .disabled(viewModel.isConnecting)
        }
    }

    @ViewBuilder
    private var serverSections: some View {
        let saved = registry.sortedEntries
        let savedURLs = Set(saved.map(\.url))
        let freshHits = viewModel.discovered.filter { !savedURLs.contains($0.url) }

        if !saved.isEmpty {
            sectionHeader("Saved")
            VStack(spacing: 8) {
                ForEach(saved) { entry in
                    Button {
                        Task { await viewModel.selectSaved(entry, router: router) }
                    } label: {
                        serverRow(
                            title: entry.displayName,
                            subtitle: entryMeta(entry),
                            systemImage: entry.id == registry.activeServerId
                                ? "checkmark.circle.fill"
                                : "server.rack"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isConnecting)
                }
            }
            .padding(.bottom, 18)
        }

        if !freshHits.isEmpty || viewModel.isScanning {
            sectionHeader("Discovered")
            VStack(spacing: 8) {
                ForEach(freshHits) { hit in
                    Button {
                        Task { await viewModel.selectDiscovered(hit, router: router) }
                    } label: {
                        serverRow(
                            title: hit.displayName,
                            subtitle: "Found · \(hit.url)",
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isConnecting)
                }
                if viewModel.isScanning && freshHits.isEmpty {
                    Text("Scanning your network for Prairie…")
                        .font(.continuumCaption)
                        .foregroundStyle(Color.auroraInkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 18)
        }

        if !viewModel.isScanning && saved.isEmpty && freshHits.isEmpty {
            Text("No servers yet — wait for the scan, or add a URL manually.")
                .font(.continuumCaption)
                .foregroundStyle(Color.auroraInkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(Color.auroraInkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }

    private func serverRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.auroraInk)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.continuumSubheadline)
                    .foregroundStyle(Color.auroraInk)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.continuumCaption)
                    .foregroundStyle(Color.auroraInkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.auroraInkTertiary)
        }
        .padding(16)
        .auroraGlass(cornerRadius: 16)
        .contentShape(Rectangle())
    }

    private func entryMeta(_ entry: ServerEntry) -> String {
        let prefix = entry.id == registry.activeServerId ? "Active · " : "Saved · "
        return prefix + entry.url
    }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
    private var tvOSBody: some View {
        ZStack {
            AuroraBackdrop(variant: .server, scrim: .soft)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    tvHero
                    tvActions
                    if let status = viewModel.statusText, !status.isEmpty {
                        Text(status)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.auroraInkSecondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }
                    if let error = viewModel.errorText {
                        Text(error)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.continuumError)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                    }
                    tvSections
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.bottom, 64)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaPadding(.horizontal, ContinuumTheme.Skyline.safeAreaX)
            .safeAreaPadding(.top, 48)
            .defaultFocus($focusedRow, defaultFocusRow)
        }
        .ignoresSafeArea()
        .task { await viewModel.startAutoScanIfNeeded() }
        .onDisappear { viewModel.cancelScan() }
    }

    private var tvHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PrairieWordmarkView(width: 132)
                Spacer(minLength: 0)
                AuroraJourneyProgress(currentStep: 1)
                    .frame(width: 430)
            }
            AuroraEyebrow(text: "Connect")
            Text("Choose a server")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Color.auroraInk)
            Text("Choose a saved server or one found on your LAN. Sign-in comes next.")
                .font(.system(size: 20))
                .foregroundStyle(Color.auroraInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var tvActions: some View {
        HStack(spacing: 16) {
            Button {
                Task { await viewModel.startScan(includeDeep: true) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 22, weight: .semibold))
                    Text(viewModel.isScanning ? "Scanning…" : "Scan again")
                        .font(.system(size: 26))
                }
            }
            .buttonStyle(TVSettingsPaneRowStyle())
            .focused($focusedRow, equals: .scan)
            .disabled(viewModel.isScanning || viewModel.isConnecting)

            Button {
                router.navigate(to: .serverSetup)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Add manually")
                        .font(.system(size: 26))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .opacity(0.55)
                }
            }
            .buttonStyle(TVSettingsPaneRowStyle())
            .focused($focusedRow, equals: .addManual)
            .disabled(viewModel.isConnecting)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var tvSections: some View {
        let saved = registry.sortedEntries
        let savedURLs = Set(saved.map(\.url))
        let freshHits = viewModel.discovered.filter { !savedURLs.contains($0.url) }

        if !saved.isEmpty {
            TVSettingsSectionHeader("SAVED")
            ForEach(saved) { entry in
                Button {
                    Task { await viewModel.selectSaved(entry, router: router) }
                } label: {
                    tvServerLabel(
                        title: entry.displayName,
                        subtitle: entryMeta(entry),
                        systemImage: entry.id == registry.activeServerId
                            ? "checkmark.circle.fill"
                            : "server.rack"
                    )
                }
                .buttonStyle(TVSettingsPaneRowStyle())
                .focused($focusedRow, equals: .saved(entry.id))
                .disabled(viewModel.isConnecting)
            }
        }

        if !freshHits.isEmpty || viewModel.isScanning {
            TVSettingsSectionHeader("DISCOVERED")
            ForEach(freshHits) { hit in
                Button {
                    Task { await viewModel.selectDiscovered(hit, router: router) }
                } label: {
                    tvServerLabel(
                        title: hit.displayName,
                        subtitle: "Found · \(hit.url)",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                }
                .buttonStyle(TVSettingsPaneRowStyle())
                .focused($focusedRow, equals: .discovered(hit.url))
                .disabled(viewModel.isConnecting)
            }
            if viewModel.isScanning && freshHits.isEmpty {
                TVSettingsFooter("Scanning your network for Prairie…")
            }
        }

        if !viewModel.isScanning && saved.isEmpty && freshHits.isEmpty {
            TVSettingsFooter("No servers yet — wait for the scan, or add a URL manually.")
        }
    }

    private func tvServerLabel(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 19))
                    .opacity(0.62)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .opacity(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryMeta(_ entry: ServerEntry) -> String {
        let prefix = entry.id == registry.activeServerId ? "Active · " : "Saved · "
        return prefix + entry.url
    }

    private enum FocusRow: Hashable {
        case scan
        case addManual
        case saved(String)
        case discovered(String)
    }

    private var defaultFocusRow: FocusRow {
        if let first = registry.sortedEntries.first {
            return .saved(first.id)
        }
        return .scan
    }
    #endif
}

// MARK: - View model

@Observable
@MainActor
final class ConnectServerListViewModel {
    var discovered: [LanDiscovery.DiscoveryHit] = []
    var isScanning = false
    var isConnecting = false
    var statusText: String?
    var errorText: String?

    private var didAutoScan = false
    private var scanTask: Task<Void, Never>?
    private let scanner = LanDiscoveryScanner()

    private func discoveryBaseHosts() -> [String] {
        var out: [String] = []
        var seen = Set<String>()

        func push(host: String?) {
            guard let host, !host.isEmpty else { return }
            let key = host.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(host)
        }

        for entry in ServerRegistry.shared.entries {
            push(host: URL(string: entry.url)?.host)
        }

        let last = SharedStorage.suite.string(forKey: SharedStorage.serverUrlKey)
        push(host: URL(string: last ?? "")?.host)

        return out
    }

    func startAutoScanIfNeeded() async {
        guard !didAutoScan else { return }
        didAutoScan = true
        await startScan(includeDeep: true)
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func startScan(includeDeep: Bool) async {
        scanTask?.cancel()
        let task = Task { await self.runScan(includeDeep: includeDeep) }
        scanTask = task
        await task.value
    }

    private func runScan(includeDeep: Bool) async {
        isScanning = true
        errorText = nil
        discovered = []
        statusText = "Looking for Prairie servers on your network…"
        defer {
            if !Task.isCancelled {
                isScanning = false
            }
        }

        var hits = await scanner.run(
            options: LanDiscoveryScanner.ScanOptions(deepScan: false, baseHosts: discoveryBaseHosts()),
            onHit: { [weak self] next in
                Task { @MainActor in
                    self?.discovered = next
                }
            },
            onProgress: { [weak self] done, total in
                Task { @MainActor in
                    self?.statusText = "Quick scan \(done)/\(total)…"
                }
            }
        )
        if Task.isCancelled { return }
        discovered = hits

        if includeDeep {
            statusText = "Deep LAN scan…"
            let deepHits = await scanner.run(
                options: LanDiscoveryScanner.ScanOptions(deepScan: true, baseHosts: discoveryBaseHosts()),
                onHit: { [weak self] next in
                    Task { @MainActor in
                        guard let self else { return }
                        self.discovered = Self.mergeHitLists(self.discovered, next)
                    }
                },
                onProgress: { [weak self] done, total in
                    Task { @MainActor in
                        self?.statusText = "Deep scan \(done)/\(total)…"
                    }
                }
            )
            if Task.isCancelled { return }
            hits = Self.mergeHitLists(hits, deepHits)
            discovered = hits
        }

        statusText = hits.isEmpty
            ? "No Prairie servers found — add one manually or scan again"
            : "Found \(hits.count) server(s)"
    }

    func selectSaved(_ entry: ServerEntry, router: AppRouter) async {
        guard !isConnecting else { return }
        cancelScan()
        isConnecting = true
        errorText = nil
        defer { isConnecting = false }

        let hasAccess = SharedKeychain().get(TokenStore.accessTokenKey(for: entry.id)) != nil
        if hasAccess {
            await ServerRegistry.shared.switchTo(serverId: entry.id)
            refreshAuthState(router: router)
            return
        }

        do {
            let status = try await AuthService.shared.checkServer(url: entry.url)
            router.path = NavigationPath()
            router.authState = .needsLogin
            if status.needsSetup {
                router.navigate(to: .serverNeedsSetup)
            }
        } catch {
            errorText = "Could not reach \(entry.displayName)."
        }
    }

    func selectDiscovered(_ hit: LanDiscovery.DiscoveryHit, router: AppRouter) async {
        guard !isConnecting else { return }
        cancelScan()
        isConnecting = true
        errorText = nil
        defer { isConnecting = false }

        do {
            let status = try await AuthService.shared.checkServer(url: hit.url)
            router.path = NavigationPath()
            router.authState = .needsLogin
            if status.needsSetup {
                router.navigate(to: .serverNeedsSetup)
            }
        } catch {
            errorText = "Could not reach \(hit.displayName)."
        }
    }

    private func refreshAuthState(router: AppRouter) {
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

    private static func mergeHitLists(
        _ base: [LanDiscovery.DiscoveryHit],
        _ extra: [LanDiscovery.DiscoveryHit]
    ) -> [LanDiscovery.DiscoveryHit] {
        var result = base
        for hit in extra {
            if let index = result.firstIndex(where: { $0.url == hit.url }) {
                result[index] = hit
            } else {
                result.append(hit)
            }
        }
        return result
    }
}
