#if !os(tvOS)
import SwiftUI

/// The series action row's Download control. It opens
/// `SeriesDownloadSheet`, which downloads once or monitors the series.
/// Reads `DownloadManager.shared` directly so it reflects live state.
struct SeriesDownloadButton: View {
    let detail: ItemDetail
    let seasons: [Season]
    let selectedSeason: Season?
    /// The highlighted episode and the version its selector shows.
    let episode: EpisodeListItem?
    let episodeFileId: Int?

    private var manager: DownloadManager { DownloadManager.shared }
    @State private var showOptions = false

    private var seriesId: String { detail.seriesId ?? detail.contentId }
    private var isMonitored: Bool { manager.subscription(forSeriesId: seriesId)?.active == true }

    /// Filled, borderless circle over a caption, matching
    /// `PhoneLabeledAction`'s metrics.
    var body: some View {
        Button {
            showOptions = true
        } label: {
            switch style {
            case .circle: circleLabel
            case .labeled: labeledLabel
            }
        }
        .accessibilityLabel("Download or monitor series")
        .accessibilityValue(isMonitored ? "Monitored" : "Not monitored")
        // Chaining sheets from `onDismiss` waits out the real dismiss
        // animation instead of guessing a delay — a fixed sleep silently
        // fails to present when teardown runs long (slow device,
        // accessibility animations, low power).
        .sheet(item: $activeSheet, onDismiss: {
            sheetOnScreen = false
            if let pendingSheet {
                self.pendingSheet = nil
                activeSheet = pendingSheet
            } else if let pendingEpisodeError {
                self.pendingEpisodeError = nil
                episodeErrorMessage = pendingEpisodeError
        }) { sheet in
            switch sheet {
            case .downloadOptions:
                SeriesDownloadOptionsSheet(
                    seriesId: seriesId,
                    seriesTitle: detail.title,
                    seasons: seasons,
                    selectedSeason: selectedSeason,
                    cachedEpisodesBySeason: cachedEpisodesBySeason,
                    posterThumbhash: detail.posterThumbhash,
                    canDownloadSeason: manager.canDownloadSeason,
                    canMonitorSeries: manager.canMonitorSeries,
                    isMonitored: isMonitored,
                    episodeTarget: episodeTarget,
                    onEpisodeOptions: { target in
                        optionsTarget = target
                        pendingSheet = .episodeOptions
                    },
                    onMonitor: { pendingSheet = .monitor }
                )
                .environment(\.browseLibraryId, libraryId)
            case .episodeOptions:
                if let target = optionsTarget {
                    DownloadOptionsSheet(
                        title: "\(target.code) · \(target.title)",
                        versions: target.versions,
                        selectedVersionFileId: target.selectedFileId,
                        lastVersionFileId: target.lastFileId,
                        onStart: { startEpisodeDownload($0, target: target) }
                    )
                }
            case .monitor:
                SeriesMonitorSheet(seriesId: seriesId, seriesTitle: detail.title, seasons: seasons)
        .onChange(of: activeSheet) { _, sheet in
            if sheet != nil { sheetOnScreen = true }
        // The options sheet dismisses as soon as it hands off, so a failed
        // registration has to surface from here.
        .alert(
            "Download Failed",
            isPresented: Binding(
                get: { episodeErrorMessage != nil },
                set: { if !$0 { episodeErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(episodeErrorMessage ?? "")
    }

    private func startEpisodeDownload(_ options: DownloadRequestOptions, target: SeriesEpisodeDownloadTarget) {
        Task {
            do {
                try await manager.downloadEpisode(
                    episodeId: target.episode.contentId,
                    displayTitle: target.title,
                    displaySubtitle: target.displaySubtitle,
                    fileId: options.fileId,
                    quality: options.quality
            } catch DownloadError.registrationAlreadyInFlight {
                // The original request owns the Preparing state.
            } catch {
                if sheetOnScreen {
                    pendingEpisodeError = error.localizedDescription
                } else {
                    episodeErrorMessage = error.localizedDescription
}
private enum SeriesDownloadSheet: Identifiable {
    case downloadOptions
    case episodeOptions
    case monitor
    var id: String {
        switch self {
        case .downloadOptions: return "downloadOptions"
        case .episodeOptions: return "episodeOptions"
        case .monitor: return "monitor"
private struct SeriesDownloadOptionsSheet: View {
    let seriesId: String
    let seriesTitle: String
    let seasons: [Season]
    let selectedSeason: Season?
    let cachedEpisodesBySeason: [Int: [EpisodeListItem]]
    let posterThumbhash: String?
    let canDownloadSeason: Bool
    let canMonitorSeries: Bool
    let isMonitored: Bool
    let episodeTarget: SeriesEpisodeDownloadTarget?
    let onEpisodeOptions: (SeriesEpisodeDownloadTarget) -> Void
    let onMonitor: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var manager: DownloadManager { DownloadManager.shared }
    @State private var errorMessage: String?
    /// The option being registered, which shows a spinner in its row.
    @State private var workingOption: String?
    @State private var finishedCount = 0
    private var isWorking: Bool { workingOption != nil }
    var body: some View {
        NavigationStack {
            Form {
                if let episodeTarget {
                    episodeSection(episodeTarget)
                Section {
                    if !availableSeasons.isEmpty {
                        NavigationLink {
                            SeriesSeasonDownloadPicker(
                                seriesId: seriesId,
                                seriesTitle: seriesTitle,
                                seasons: availableSeasons,
                                cachedEpisodesBySeason: cachedEpisodesBySeason,
                                posterThumbhash: posterThumbhash
                            )
                        } label: {
                            // The navigation link draws its own chevron.
                            optionLabel(
                                title: "Choose Episodes",
                                detail: "Open a season and select episodes",
                                icon: "checklist",
                                showsChevron: false
                        }
                        .disabled(isWorking)
                    }
                    if canDownloadSeason, let selectedSeason {
                        optionButton(
                            title: "Download Season \(selectedSeason.seasonNumber)",
                            detail: "Original quality · \(selectedSeason.episodeCount) episode\(selectedSeason.episodeCount == 1 ? "" : "s")",
                            icon: "square.and.arrow.down.on.square",
                            option: "season"
                        ) {
                            startDownload(option: "season") {
                                try await manager.downloadSeason(seriesId: seriesId, seasonNumber: selectedSeason.seasonNumber)
                            }
                    optionButton(
                        title: "Download All Episodes",
                        detail: "Original quality",
                        icon: "arrow.down.circle",
                        option: "series"
                    ) {
                        startDownload(option: "series") {
                            try await manager.downloadSeries(seriesId: seriesId)
                } header: {
                    Text("Download")
                } footer: {
                    Text("Series and season downloads use original quality.")
                if canMonitorSeries {
                    Section("Monitoring") {
                            title: isMonitored ? "Edit Monitoring" : "Monitor Series",
                            detail: isMonitored ? "Change auto-download rules" : "Auto-download future episodes",
                            icon: "antenna.radiowaves.left.and.right"
                            dismiss()
                            onMonitor()
                        if isMonitored {
                            Button(role: .destructive) {
                                if let sub = manager.subscription(forSeriesId: seriesId) {
                                    Task { await manager.deleteSubscription(id: sub.id) }
                                }
                                dismiss()
                            } label: {
                                Label("Stop Monitoring", systemImage: "xmark.circle")
            .navigationTitle(seriesTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .prairieScrollContentBackgroundHidden()
            .prairieSheetBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            Text(errorMessage ?? "")
    /// The highlighted episode, downloaded with the version its selector
    /// shows. Batch rows below cannot carry a version, so this is the one
    /// place a series-page version choice reaches a download.
    @ViewBuilder
    private func episodeSection(_ target: SeriesEpisodeDownloadTarget) -> some View {
        let isRegistering = manager.isRegistering(contentId: target.episode.contentId)
        let record = manager.record(forContentId: target.episode.contentId)
        // A failed entry holds no playable bytes, so it offers a retry like
        // the episode card instead of claiming the episode is downloaded.
        let failed = record?.localStatus == .failed
        Section {
            if (record != nil && !failed) || isRegistering {
                optionLabel(
                    title: target.code,
                    detail: "Already in Downloads",
                    icon: "checkmark.circle",
                    showsChevron: false
            } else {
                optionButton(
                    title: failed ? "Retry \(target.code)" : "Download \(target.code)",
                    detail: episodeVersionDetail(target),
                    icon: failed ? "arrow.clockwise" : "arrow.down.to.line",
                    option: "episode"
                ) {
                    startDownload(option: "episode") {
                        try await manager.downloadEpisode(
                            seriesId: seriesId,
                            episodeId: target.episode.contentId,
                            displayTitle: target.title,
                            displaySubtitle: target.displaySubtitle,
                            posterThumbhash: posterThumbhash,
                            fileId: target.displayedVersion?.fileId,
                            quality: DownloadSettings.shared.resolvedFormat(
                                allowedFormats: manager.capability?.qualityPresets ?? []
                        )
            // Stays available once downloaded, like the movie page's
            // Download Options, so a different version replaces the entry.
            if !isRegistering {
                    title: "Episode Options…",
                    detail: "Choose the version and quality",
                    icon: "slider.horizontal.3"
                    dismiss()
                    onEpisodeOptions(target)
        } header: {
            Text("Episode")
    private func episodeVersionDetail(_ target: SeriesEpisodeDownloadTarget) -> String {
        guard let version = target.displayedVersion else { return target.title }
        let label = DetailPlaybackFormatting.versionPrimaryText(version)
        guard let estimate = DownloadSizeEstimate.estimate(versions: target.versions, fileId: version.fileId) else {
            return label
        return "\(label) · \(estimate.sizeLabel)"
    private var availableSeasons: [Season] {
        let sorted = seasons.sortedForDisplay()
        if sorted.isEmpty, let selectedSeason { return [selectedSeason] }
        return sorted
    /// Run a download request, dismissing only on success — a silent
    /// `try?` here made an offline/unauthenticated tap look like it worked.
    private func startDownload(option: String, _ work: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        workingOption = option
                try await work()
                finishedCount += 1
                dismiss()
                errorMessage = error.localizedDescription
            workingOption = nil
    private func optionButton(
        title: String,
        detail: String,
        icon: String,
        option: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            optionLabel(title: title, detail: detail, icon: icon, showsSpinner: option != nil && workingOption == option)
        .buttonStyle(.plain)
        .disabled(isWorking)
        .sensoryFeedback(.success, trigger: finishedCount)
    private func optionLabel(
        title: String, detail: String, icon: String, showsSpinner: Bool = false, showsChevron: Bool = true
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.prairieOnSurface)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.prairieOnSurface)
                Text(detail)
                    .font(.prairieCaption)
                    .foregroundColor(.prairieSecondaryText)
            Spacer(minLength: 8)
            if showsSpinner {
                ProgressView()
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
        .padding(.vertical, 4)
        // The whole row answers a tap, not just its text and icons.
        .contentShape(Rectangle())
/// First level of the single-episode flow. Keeping seasons as navigation
/// destinations makes the download sheet scale to long-running series without
/// turning the first screen into one enormous checklist.
private struct SeriesSeasonDownloadPicker: View {
        List {
            Section {
                ForEach(seasons.sortedForDisplay()) { season in
                    NavigationLink {
                        SeriesEpisodeDownloadPicker(
                            seriesTitle: seriesTitle,
                            season: season,
                            initialEpisodes: cachedEpisodesBySeason[season.seasonNumber] ?? [],
                            posterThumbhash: season.posterThumbhash ?? posterThumbhash
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(season.downloadDisplayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.prairieOnSurface)
                            Text("\(season.episodeCount) episode\(season.episodeCount == 1 ? "" : "s")")
                                .font(.prairieCaption)
                                .foregroundColor(.prairieSecondaryText)
                        .padding(.vertical, 4)
            } header: {
                Text("Select a season")
        .navigationTitle("Choose Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .prairieScrollContentBackgroundHidden()
        .prairieSheetBackground()
/// Native multi-selection for one season. A season's episode list is reused
/// from the detail model when available and fetched on demand otherwise.
private struct SeriesEpisodeDownloadPicker: View {
    @Environment(\.browseLibraryId) private var browseLibraryId
    let season: Season
    @State private var episodes: [EpisodeListItem]
    @State private var selectedEpisodeIds: Set<String> = []
    @State private var isLoading = false
    @State private var isWorking = false
    init(
        seriesId: String,
        seriesTitle: String,
        season: Season,
        initialEpisodes: [EpisodeListItem],
        posterThumbhash: String?
    ) {
        self.seriesId = seriesId
        self.seriesTitle = seriesTitle
        self.season = season
        self.posterThumbhash = posterThumbhash
        _episodes = State(initialValue: Self.sorted(initialEpisodes))
    private var selectableEpisodeIds: Set<String> {
        Set(episodes.compactMap { episode in
            isSelectable(episode) ? episode.contentId : nil
        })
    private var selectedEpisodes: [EpisodeListItem] {
        episodes.filter {
            selectedEpisodeIds.contains($0.contentId) && isSelectable($0)
    private var allSelectableAreSelected: Bool {
        !selectableEpisodeIds.isEmpty
            && selectableEpisodeIds.isSubset(of: selectedEpisodeIds)
        Group {
            if isLoading, episodes.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading episodes…")
                        .font(.prairieCaption)
                        .foregroundColor(.prairieSecondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if episodes.isEmpty {
                EmptyStateView(
                    icon: "film.stack",
                    title: "No Episodes",
                    subtitle: "No downloadable episodes were found for this season."
                List {
                    Section {
                        ForEach(episodes) { episode in
                            episodeRow(episode)
                    } header: {
                        HStack {
                            Text("Episodes")
                            Spacer()
                            if !selectableEpisodeIds.isEmpty {
                                Button(allSelectableAreSelected ? "Clear" : "Select All") {
                                    toggleSelectAll()
                                .textCase(nil)
                .prairieScrollContentBackgroundHidden()
        .navigationTitle(season.downloadDisplayName)
        .safeAreaInset(edge: .bottom) {
            if !episodes.isEmpty {
                downloadBar
        .task { await loadEpisodesIfNeeded() }
            "Couldn't Continue",
    private var downloadBar: some View {
        Button(action: startSelectedDownloads) {
            HStack(spacing: 9) {
                if isWorking {
                        .controlSize(.small)
                        .tint(.black)
                    Image(systemName: "arrow.down.to.line")
                Text(downloadButtonTitle)
                    .fontWeight(.bold)
            .font(.system(size: 15))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(selectedEpisodes.isEmpty ? Color.prairieDisabled : Color.prairieOnSurface)
            .foregroundColor(.black)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .disabled(selectedEpisodes.isEmpty || isWorking)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    private var downloadButtonTitle: String {
        let count = selectedEpisodes.count
        if count == 0 { return "Select Episodes" }
        return "Download \(count) Episode\(count == 1 ? "" : "s")"
    private func episodeRow(_ episode: EpisodeListItem) -> some View {
        let selectable = isSelectable(episode)
        return Button {
            guard selectable, !isWorking else { return }
            toggle(episode.contentId)
        } label: {
            HStack(spacing: 12) {
                selectionIndicator(for: episode)
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title ?? "Episode \(episode.episodeNumber)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.prairieOnSurface)
                        .lineLimit(1)
                    Text(episodeDetailText(episode))
                Spacer(minLength: 8)
                if let status = statusText(for: episode) {
                    Text(status)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusTint(for: episode))
            .padding(.vertical, 4)
            VStack(spacing: 6) {
                Image(systemName: isMonitored ? "arrow.down.circle.fill" : "arrow.down.to.line")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(Color.prairieOnSurface)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(isMonitored ? 0.18 : 0.10)))
                Text("Download")
                    .prairieScaledFont(size: 10, weight: .medium, relativeTo: .caption2)
                    .foregroundColor(Color.prairieOnSurface.opacity(isMonitored ? 0.92 : 0.6))
                    .phoneActionCaption()
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Download")
        .accessibilityValue(isMonitored ? "Monitoring" : "")
        .sheet(isPresented: $showOptions) {
            SeriesDownloadSheet(
                seriesId: seriesId,
                seriesTitle: detail.title,
                seasons: seasons,
                selectedSeason: selectedSeason,
                episode: episode,
                episodeFileId: episodeFileId,
                posterThumbhash: detail.posterThumbhash
            )
            guard !Task.isCancelled else { return }
            episodes = Self.sorted(response.episodes)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startSelectedDownloads() {
        let targets = selectedEpisodes
        guard !targets.isEmpty, !isWorking else { return }
        isWorking = true
        Task {
            do {
                for episode in targets {
                    guard isSelectable(episode) else {
                        selectedEpisodeIds.remove(episode.contentId)
                        continue
                    }
                    try await manager.downloadEpisode(
                        seriesId: seriesId,
                        episodeId: episode.contentId,
                        displayTitle: episode.title ?? "Episode \(episode.episodeNumber)",
                        displaySubtitle: "S\(episode.seasonNumber) · E\(episode.episodeNumber)",
                        posterThumbhash: posterThumbhash,
                        quality: DownloadSettings.shared.resolvedFormat(
                            allowedFormats: manager.capability?.qualityPresets ?? []
                        )
                    )
                    selectedEpisodeIds.remove(episode.contentId)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
    private static func sorted(_ episodes: [EpisodeListItem]) -> [EpisodeListItem] {
        episodes.sorted { lhs, rhs in
            if lhs.episodeNumber != rhs.episodeNumber {
                return lhs.episodeNumber < rhs.episodeNumber
            return lhs.contentId < rhs.contentId
}
/// Create / edit a series-monitoring subscription. The retention fields
/// (`delete_watched`, `max_storage_bytes`) are client-enforced; the server
/// only soft-gates auto-registration.
struct SeriesMonitorSheet: View {
    let seriesId: String
    let seriesTitle: String
    let seasons: [Season]
    @Environment(\.dismiss) private var dismiss
    private var manager: DownloadManager { DownloadManager.shared }
    @State private var mode: SubscriptionMode = .all
    @State private var selectedSeasons: Set<Int> = []
    @State private var deleteWatched: Bool = DownloadSettings.shared.defaultDeleteWatched
    @State private var maxStorageGB: Int = DownloadSettings.shared.defaultMaxStorageGB
    @State private var isSaving = false
    @State private var saveError: String?
    private var existing: DownloadSubscription? { manager.subscription(forSeriesId: seriesId) }
    private var availableModes: [SubscriptionMode] {
        manager.monitoringModes.isEmpty ? SubscriptionMode.allCases : manager.monitoringModes
    var body: some View {
        NavigationStack {
            Form {
                Section("Keep Downloaded") {
                    Picker("Episodes", selection: $mode) {
                        ForEach(availableModes, id: \.self) { Text($0.displayName).tag($0) }
                    if mode == .specificSeasons {
                        ForEach(seasons) { season in
                            Toggle("Season \(season.seasonNumber)", isOn: Binding(
                                get: { selectedSeasons.contains(season.seasonNumber) },
                                set: { isOn in
                                    if isOn { selectedSeasons.insert(season.seasonNumber) }
                                    else { selectedSeasons.remove(season.seasonNumber) }
                                }
                            ))
                            .tint(.prairieSwitchOn)
                        }
                Section("Storage") {
                    Toggle("Delete watched episodes", isOn: $deleteWatched)
                        .tint(.prairieSwitchOn)
                    Picker("Limit", selection: $maxStorageGB) {
                        ForEach(storageLimitOptionsGB, id: \.self) { gb in
                            Text(gb == 0 ? "Unlimited" : "\(gb) GB").tag(gb)
            .navigationTitle(existing == nil ? "Monitor Series" : "Edit Monitoring")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "square.and.arrow.down", action: save)
                        .disabled(isSaving || (mode == .specificSeasons && selectedSeasons.isEmpty))
            .onAppear(perform: prefill)
            .alert(
                "Couldn't Save Monitoring",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
    /// Common caps, plus the stored value when it doesn't match one —
    /// subscriptions written by the old stepper (or another client) must
    /// stay representable rather than silently snapping to a preset.
    private var storageLimitOptionsGB: [Int] {
        var options = [0, 10, 25, 50, 100]
        if !options.contains(maxStorageGB) {
            options.append(maxStorageGB)
            options.sort()
        return options
    private func prefill() {
        guard let existing else { return }
        mode = SubscriptionMode(rawValue: existing.mode) ?? .all
        selectedSeasons = Set(existing.seasonNumbers ?? [])
        deleteWatched = existing.deleteWatched
        maxStorageGB = Int(existing.maxStorageBytes / DownloadSettings.bytesPerGB)
    private func save() {
        isSaving = true
        let bytes = Int64(maxStorageGB) * DownloadSettings.bytesPerGB
        let seasonNumbers = mode == .specificSeasons ? Array(selectedSeasons).sorted() : nil
                if let existing {
                    try await manager.updateSubscription(
                        id: existing.id,
                        mode: mode,
                        seasonNumbers: seasonNumbers,
                        deleteWatched: deleteWatched,
                        maxStorageBytes: bytes,
                        active: true
                } else {
                    try await manager.createSubscription(
                        seriesTitle: seriesTitle,
                        maxStorageBytes: bytes
                // Keep the sheet up so the edits aren't lost — the user can
                // retry or cancel once they've seen why the save failed.
                saveError = error.localizedDescription
            isSaving = false
        }
    }
}
#endif
