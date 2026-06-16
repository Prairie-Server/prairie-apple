#if os(tvOS)
import SwiftUI

/// Pre-Play playback-selection row shown under the hero actions. Renders
/// Edition · Version · Audio · Subtitles as squared menu buttons, mirroring
/// the Silo webapp. Each selector auto-hides when there is no real choice.
/// Uses the detail view's existing version/audio/subtitle callbacks; Edition
/// is derived from `FileVersion.edition` and selecting one routes through
/// `onSelectVersion`.
struct TVPlaybackSelectorRow: View {
    let versions: [FileVersion]
    let currentVersion: FileVersion?
    let selectedVersionFileId: Int?
    let selectedAudioTrackIndex: Int?
    let selectedSubtitleTrackIndex: Int?
    let onSelectVersion: (Int?) -> Void
    let onSelectAudioTrack: (Int?) -> Void
    let onSelectSubtitleTrack: (Int?) -> Void

    private var editions: [PlaybackEditions.Edition] { PlaybackEditions.editions(from: versions) }
    private var audioTracks: [AudioTrack] { currentVersion?.audioTracks ?? [] }
    private var subtitleTracks: [SubtitleTrack] { currentVersion?.subtitleTracks ?? [] }

    var body: some View {
        if hasAnySelector {
            HStack(spacing: 16) {
                if editions.count > 1 { editionSelector }
                if versions.count > 1 { versionSelector }
                if audioTracks.count > 1 { audioSelector }
                if currentVersion != nil { subtitleSelector }
            }
            .focusSection()
        }
    }

    private var hasAnySelector: Bool {
        editions.count > 1 || versions.count > 1 || audioTracks.count > 1 || currentVersion != nil
    }

    // MARK: - Edition

    private var currentEdition: PlaybackEditions.Edition? {
        PlaybackEditions.edition(forFileId: currentVersion?.fileId, in: versions) ?? editions.first
    }

    private var editionSelector: some View {
        TVSelectorButton(icon: "rectangle.stack", label: "Edition", value: currentEdition?.label ?? "—") {
            ForEach(editions) { edition in
                Button {
                    let best = DetailVersionSelection.displayVersion(
                        versions: edition.versions, selectedFileId: nil, lastFileId: nil
                    )
                    onSelectVersion(best?.fileId)
                } label: {
                    selectorMenuItem(title: edition.label,
                                     detail: "\(edition.versions.count) version\(edition.versions.count == 1 ? "" : "s")",
                                     isSelected: currentEdition?.id == edition.id)
                }
            }
        }
    }

    // MARK: - Version

    private var versionSelector: some View {
        TVSelectorButton(icon: "4k.tv", label: "Version", value: versionShortLabel(currentVersion)) {
            Button { onSelectVersion(nil) } label: {
                selectorMenuItem(title: "Auto", detail: "Best match for this device", isSelected: selectedVersionFileId == nil)
            }
            ForEach(scopedVersions) { version in
                Button { onSelectVersion(version.fileId) } label: {
                    selectorMenuItem(title: versionShortLabel(version),
                                     detail: versionDetailLabel(version),
                                     isSelected: selectedVersionFileId == version.fileId)
                }
            }
        }
    }

    private var scopedVersions: [FileVersion] {
        if editions.count > 1, let edition = currentEdition { return edition.versions }
        return versions
    }

    private func versionShortLabel(_ version: FileVersion?) -> String {
        guard let version else { return "Auto" }
        var tokens: [String] = []
        if let res = version.resolution, !res.isEmpty { tokens.append(res.uppercased()) }
        if version.hdr == true { tokens.append("HDR") }
        return tokens.isEmpty ? "Auto" : tokens.joined(separator: " · ")
    }

    private func versionDetailLabel(_ version: FileVersion) -> String {
        var tokens: [String] = []
        if let codec = version.codecVideo, !codec.isEmpty { tokens.append(codec.uppercased()) }
        if let container = version.container, !container.isEmpty { tokens.append(container.uppercased()) }
        return tokens.joined(separator: " · ")
    }

    // MARK: - Audio

    private var audioSelector: some View {
        TVSelectorButton(icon: "speaker.wave.2", label: "Audio", value: audioValueLabel) {
            Button { onSelectAudioTrack(nil) } label: {
                selectorMenuItem(title: "Auto", detail: "Use the file default track", isSelected: selectedAudioTrackIndex == nil)
            }
            ForEach(audioTracks) { track in
                Button { onSelectAudioTrack(track.index) } label: {
                    selectorMenuItem(title: audioTitle(track), detail: audioDetail(track),
                                     isSelected: selectedAudioTrackIndex == (track.index ?? -1))
                }
            }
        }
    }

    private var audioValueLabel: String {
        if selectedAudioTrackIndex == nil { return "Auto" }
        if let track = audioTracks.first(where: { ($0.index ?? -1) == selectedAudioTrackIndex }) { return audioTitle(track) }
        return "Auto"
    }

    private func audioTitle(_ track: AudioTrack) -> String {
        if let title = track.title, !title.isEmpty { return title }
        var tokens: [String] = []
        if let lang = track.language, !lang.isEmpty { tokens.append(lang.uppercased()) }
        if let codec = track.codec, !codec.isEmpty { tokens.append(codec.uppercased()) }
        return tokens.isEmpty ? "Track \((track.index ?? 0) + 1)" : tokens.joined(separator: " ")
    }

    private func audioDetail(_ track: AudioTrack) -> String {
        track.isDefault == true ? "Default" : ""
    }

    // MARK: - Subtitles

    private var subtitleSelector: some View {
        TVSelectorButton(icon: "captions.bubble", label: "Subtitles", value: subtitleValueLabel) {
            Button { onSelectSubtitleTrack(nil) } label: {
                selectorMenuItem(title: "Auto", detail: "Use your subtitle preferences", isSelected: selectedSubtitleTrackIndex == nil)
            }
            Button { onSelectSubtitleTrack(-1) } label: {
                selectorMenuItem(title: "Off", detail: "Start without subtitles", isSelected: selectedSubtitleTrackIndex == -1)
            }
            ForEach(subtitleTracks) { track in
                Button { onSelectSubtitleTrack(track.index) } label: {
                    selectorMenuItem(title: subtitleTitle(track), detail: subtitleDetail(track),
                                     isSelected: selectedSubtitleTrackIndex == (track.index ?? -1))
                }
            }
        }
    }

    private var subtitleValueLabel: String {
        if selectedSubtitleTrackIndex == nil { return "Auto" }
        if selectedSubtitleTrackIndex == -1 { return "Off" }
        if let track = subtitleTracks.first(where: { ($0.index ?? -1) == selectedSubtitleTrackIndex }) { return subtitleTitle(track) }
        return "Auto"
    }

    private func subtitleTitle(_ track: SubtitleTrack) -> String {
        if let title = track.title, !title.isEmpty { return title }
        if let lang = track.language, !lang.isEmpty { return lang.uppercased() }
        return "Track \((track.index ?? 0) + 1)"
    }

    private func subtitleDetail(_ track: SubtitleTrack) -> String {
        var tokens: [String] = []
        if track.forced == true { tokens.append("Forced") }
        if track.isDefault == true { tokens.append("Default") }
        return tokens.joined(separator: " · ")
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
        .buttonStyle(TVPillButtonStyle(kind: .secondary))
    }
}
#endif
