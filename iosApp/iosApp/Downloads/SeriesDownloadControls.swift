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
            }
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
        }
    }
}

/// First level of the single-episode flow. Keeping seasons as navigation
/// destinations makes the download sheet scale to long-running series without
/// turning the first screen into one enormous checklist.
private struct SeriesSeasonDownloadPicker: View {
    let seriesId: String
    let seriesTitle: String
    let seasons: [Season]
    let cachedEpisodesBySeason: [Int: [EpisodeListItem]]
    let posterThumbhash: String?

    var body: some View {
        List {
            Section {
                ForEach(seasons.sortedForDisplay()) { season in
                    NavigationLink {
                        SeriesEpisodeDownloadPicker(
                            seriesId: seriesId,
                            seriesTitle: seriesTitle,
                            season: season,
                            initialEpisodes: cachedEpisodesBySeason[season.seasonNumber] ?? [],
                            posterThumbhash: season.posterThumbhash ?? posterThumbhash
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(season.downloadDisplayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.prairieOnSurface)
                            Text("\(season.episodeCount) episode\(season.episodeCount == 1 ? "" : "s")")
                                .font(.prairieCaption)
                                .foregroundColor(.prairieSecondaryText)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Select a season")
            }
        }
        .navigationTitle("Choose Episodes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .prairieScrollContentBackgroundHidden()
        .prairieSheetBackground()
    }
}

/// Native multi-selection for one season. A season's episode list is reused
/// from the detail model when available and fetched on demand otherwise.
private struct SeriesEpisodeDownloadPicker: View {
    @Environment(\.browseLibraryId) private var browseLibraryId
    let seriesId: String
    let seriesTitle: String
    let season: Season
    let posterThumbhash: String?

    @Environment(\.dismiss) private var dismiss
    private var manager: DownloadManager { DownloadManager.shared }

    @State private var episodes: [EpisodeListItem]
    @State private var selectedEpisodeIds: Set<String> = []
    @State private var isLoading = false
    @State private var isWorking = false
    @State private var errorMessage: String?

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
    }

    private var selectableEpisodeIds: Set<String> {
        Set(episodes.compactMap { episode in
            isSelectable(episode) ? episode.contentId : nil
        })
    }

    private var selectedEpisodes: [EpisodeListItem] {
        episodes.filter {
            selectedEpisodeIds.contains($0.contentId) && isSelectable($0)
        }
    }

    private var allSelectableAreSelected: Bool {
        !selectableEpisodeIds.isEmpty
            && selectableEpisodeIds.isSubset(of: selectedEpisodeIds)
    }

    var body: some View {
        Group {
            if isLoading, episodes.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading episodes…")
                        .font(.prairieCaption)
                        .foregroundColor(.prairieSecondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if episodes.isEmpty {
                EmptyStateView(
                    icon: "film.stack",
                    title: "No Episodes",
                    subtitle: "No downloadable episodes were found for this season."
                )
            } else {
                List {
                    Section {
                        ForEach(episodes) { episode in
                            episodeRow(episode)
                        }
                    } header: {
                        HStack {
                            Text("Episodes")
                            Spacer()
                            if !selectableEpisodeIds.isEmpty {
                                Button(allSelectableAreSelected ? "Clear" : "Select All") {
                                    toggleSelectAll()
                                }
                                .textCase(nil)
                            }
                        }
                    }
                }
                .prairieScrollContentBackgroundHidden()
            }
        }
        .prairieSheetBackground()
        .navigationTitle(season.downloadDisplayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            if !episodes.isEmpty {
                downloadBar
            }
        }
        .task { await loadEpisodesIfNeeded() }
        .alert(
            "Couldn't Continue",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var downloadBar: some View {
        Button(action: startSelectedDownloads) {
            HStack(spacing: 9) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.black)
                } else {
                    Image(systemName: "arrow.down.to.line")
                }
                Text(downloadButtonTitle)
                    .fontWeight(.bold)
            }
            .font(.system(size: 15))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(selectedEpisodes.isEmpty ? Color.prairieDisabled : Color.prairieOnSurface)
            .foregroundColor(.black)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedEpisodes.isEmpty || isWorking)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var downloadButtonTitle: String {
        let count = selectedEpisodes.count
        if count == 0 { return "Select Episodes" }
        return "Download \(count) Episode\(count == 1 ? "" : "s")"
    }

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
                        .font(.prairieCaption)
                        .foregroundColor(.prairieSecondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let status = statusText(for: episode) {
                    Text(status)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusTint(for: episode))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        }
    }

    private static func sorted(_ episodes: [EpisodeListItem]) -> [EpisodeListItem] {
        episodes.sorted { lhs, rhs in
            if lhs.episodeNumber != rhs.episodeNumber {
                return lhs.episodeNumber < rhs.episodeNumber
            }
            return lhs.contentId < rhs.contentId
        }
    }
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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Keep Downloaded") {
                    Picker("Episodes", selection: $mode) {
                        ForEach(availableModes, id: \.self) { Text($0.displayName).tag($0) }
                    }
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
                    }
                }
                Section("Storage") {
                    Toggle("Delete watched episodes", isOn: $deleteWatched)
                        .tint(.prairieSwitchOn)
                    Picker("Limit", selection: $maxStorageGB) {
                        ForEach(storageLimitOptionsGB, id: \.self) { gb in
                            Text(gb == 0 ? "Unlimited" : "\(gb) GB").tag(gb)
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Monitor Series" : "Edit Monitoring")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "square.and.arrow.down", action: save)
                        .disabled(isSaving || (mode == .specificSeasons && selectedSeasons.isEmpty))
                }
            }
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
            }
        }
    }

    /// Common caps, plus the stored value when it doesn't match one —
    /// subscriptions written by the old stepper (or another client) must
    /// stay representable rather than silently snapping to a preset.
    private var storageLimitOptionsGB: [Int] {
        var options = [0, 10, 25, 50, 100]
        if !options.contains(maxStorageGB) {
            options.append(maxStorageGB)
            options.sort()
        }
        return options
    }

    private func prefill() {
        guard let existing else { return }
        mode = SubscriptionMode(rawValue: existing.mode) ?? .all
        selectedSeasons = Set(existing.seasonNumbers ?? [])
        deleteWatched = existing.deleteWatched
        maxStorageGB = Int(existing.maxStorageBytes / DownloadSettings.bytesPerGB)
    }

    private func save() {
        isSaving = true
        let bytes = Int64(maxStorageGB) * DownloadSettings.bytesPerGB
        let seasonNumbers = mode == .specificSeasons ? Array(selectedSeasons).sorted() : nil
        Task {
            do {
                if let existing {
                    try await manager.updateSubscription(
                        id: existing.id,
                        mode: mode,
                        seasonNumbers: seasonNumbers,
                        deleteWatched: deleteWatched,
                        maxStorageBytes: bytes,
                        active: true
                    )
                } else {
                    try await manager.createSubscription(
                        seriesId: seriesId,
                        seriesTitle: seriesTitle,
                        mode: mode,
                        seasonNumbers: seasonNumbers,
                        deleteWatched: deleteWatched,
                        maxStorageBytes: bytes
                    )
                }
                dismiss()
            } catch {
                // Keep the sheet up so the edits aren't lost — the user can
                // retry or cancel once they've seen why the save failed.
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
#endif
