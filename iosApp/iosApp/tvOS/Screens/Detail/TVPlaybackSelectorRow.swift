#if os(tvOS)
import SwiftUI

/// Pre-Play playback-selection row shown under the hero actions. Renders
/// Version · Audio · Subtitles as squared menu buttons, mirroring the Silo
/// webapp. Edition is included only when there are multiple edition groups.
/// Once an effective playable version is known, the active playback metadata
/// stays visible.
/// Uses the detail view's existing version/audio/subtitle callbacks; Edition
/// is derived from `FileVersion.editionRaw` / `editionKey` and selecting one
/// routes through `onSelectVersion`.
struct TVPlaybackSelectorRow: View {
    private enum Layout {
        static let selectorSpacing: CGFloat = 28
    }

    let versions: [FileVersion]
    let currentVersion: FileVersion?
    let selectedVersionFileId: Int?
    let selectedAudioTrackIndex: Int?
    let selectedSubtitleTrackIndex: Int?
    let onSelectVersion: (Int?) -> Void
    let onSelectAudioTrack: (Int?) -> Void
    let onSelectSubtitleTrack: (Int?) -> Void

    private var editions: [PlaybackEditions.Edition] { PlaybackEditions.editions(from: versions) }

    var body: some View {
        if hasAnySelector {
            HStack(spacing: Layout.selectorSpacing) {
                if shouldShowEditionSelector {
                    editionSelector
                }
                versionSelector
                audioSelector
                subtitleSelector
            }
            // Stretch the focus section to the full action-area width even
            // though the buttons sit on the left. Entering a focus section is
            // resolved by the section's *bounds* overlapping the move vector,
            // so a full-width section sits under every top-row control —
            // including the far-right circle buttons (List / Watched / More).
            // A Down press from any of them then lands on the nearest selector
            // instead of skipping the row. Buttons stay left-aligned.
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
    }

    private var hasAnySelector: Bool {
        currentVersion != nil
    }

    private var shouldShowEditionSelector: Bool {
        editions.count > 1
    }

    // MARK: - Edition

    private var currentEdition: PlaybackEditions.Edition? {
        DetailPlaybackFormatting.currentEdition(
            versions: versions,
            currentVersion: currentVersion
        )
    }

    private var editionSelector: some View {
        TVSelectorButton(icon: "rectangle.stack", label: "Edition", value: currentEdition?.label ?? "Standard") {
            if editions.isEmpty {
                Button("Standard") { }.disabled(true)
            } else {
                ForEach(editions) { edition in
                    Button {
                        let best = DetailVersionSelection.displayVersion(
                            versions: edition.versions, selectedFileId: nil, lastFileId: nil
                        )
                        onSelectVersion(best?.fileId)
                    } label: {
                        selectorMenuItem(
                            title: edition.label,
                            detail: "\(edition.versions.count) version\(edition.versions.count == 1 ? "" : "s")",
                            isSelected: currentEdition?.id == edition.id
                        )
                    }
                }
            }
        }
    }

    // MARK: - Version

    private var versionSelector: some View {
        TVSelectorButton(
            icon: "4k.tv",
            label: "Version",
            value: DetailPlaybackFormatting.versionShortLabel(currentVersion)
        ) {
            Button { onSelectVersion(nil) } label: {
                selectorMenuItem(title: "Auto", detail: "Best match for this device", isSelected: selectedVersionFileId == nil)
            }
            ForEach(scopedVersions) { version in
                Button {
                    onSelectVersion(version.fileId)
                } label: {
                    selectorMenuItem(
                        title: DetailPlaybackFormatting.versionShortLabel(version),
                        detail: DetailPlaybackFormatting.versionDetailLabel(version),
                        isSelected: selectedVersionFileId == version.fileId
                    )
                }
            }
        }
    }

    private var scopedVersions: [FileVersion] {
        if editions.count > 1, let edition = currentEdition { return edition.versions }
        return versions
    }

    // MARK: - Audio

    private var audioSelector: some View {
        TVSelectorButton(
            icon: "speaker.wave.2",
            label: "Audio",
            value: DetailPlaybackFormatting.audioValueLabel(
                version: currentVersion,
                selectedAudioTrackIndex: selectedAudioTrackIndex
            )
        ) {
            Button { onSelectAudioTrack(nil) } label: {
                selectorMenuItem(title: "Auto", detail: "Use the file default track", isSelected: selectedAudioTrackIndex == nil)
            }
            let options = DetailPlaybackFormatting.audioOptions(
                version: currentVersion,
                selectedAudioTrackIndex: selectedAudioTrackIndex
            )
            if options.isEmpty {
                Button("Unknown") { }.disabled(true)
            } else {
                ForEach(options) { option in
                    Button { onSelectAudioTrack(option.ordinal) } label: {
                        selectorMenuItem(
                            title: option.title,
                            detail: option.detail,
                            isSelected: selectedAudioTrackIndex == option.ordinal
                        )
                    }
                }
            }
        }
    }

    // MARK: - Subtitles

    private var subtitleSelector: some View {
        TVSelectorButton(
            icon: "captions.bubble",
            label: "Subtitles",
            value: DetailPlaybackFormatting.subtitleValueLabel(
                version: currentVersion,
                selectedSubtitleTrackIndex: selectedSubtitleTrackIndex
            )
        ) {
            Button { onSelectSubtitleTrack(nil) } label: {
                selectorMenuItem(title: "Auto", detail: "Use your subtitle preferences", isSelected: selectedSubtitleTrackIndex == nil)
            }
            Button { onSelectSubtitleTrack(-1) } label: {
                selectorMenuItem(title: "Off", detail: "Start without subtitles", isSelected: selectedSubtitleTrackIndex == -1)
            }
            ForEach(DetailPlaybackFormatting.subtitleOptions(
                version: currentVersion,
                selectedSubtitleTrackIndex: selectedSubtitleTrackIndex
            )) { option in
                if option.isSelectable, let selectionIndex = option.selectionIndex {
                    Button { onSelectSubtitleTrack(selectionIndex) } label: {
                        selectorMenuItem(title: option.title, detail: option.detail, isSelected: option.isSelected)
                    }
                } else {
                    Button {
                    } label: {
                        selectorMenuItem(title: option.title, detail: option.detail, isSelected: false)
                    }
                    .disabled(true)
                }
            }
        }
    }

    // MARK: - Shared menu item

    @ViewBuilder
    private func selectorMenuItem(title: String, detail: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(detail.isEmpty ? title : "\(title) — \(detail)", systemImage: "checkmark")
        } else {
            Text(detail.isEmpty ? title : "\(title) — \(detail)")
        }
    }
}

/// One squared selector button: `[icon] LABEL  value  ⌄`, opening a `Menu`.
/// Matches the secondary squared button look (translucent fill + hairline).
private struct TVSelectorButton<MenuContent: View>: View {
    let icon: String
    let label: String
    let value: String
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Text(label.uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .tracking(1.0)
                    .opacity(0.6)
                Text(value).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).opacity(0.6)
            }
        }
        .menuStyle(.button)
        .buttonStyle(TVPillButtonStyle(kind: .secondary, focusTreatment: .compact))
    }
}
#endif
