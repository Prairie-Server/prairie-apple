import Foundation

enum DetailPlaybackFormatting {
    struct AudioOption: Identifiable, Hashable {
        let ordinal: Int
        let title: String
        let detail: String
        let isSelected: Bool
        var id: Int { ordinal }
    }

    struct SubtitleOption: Identifiable, Hashable {
        let selectionIndex: Int?
        let title: String
        let detail: String
        let isSelected: Bool
        let isSelectable: Bool
        let stableId: String
        var id: String { stableId }
    }

    static func versionShortLabel(_ version: FileVersion?) -> String {
        guard let version else { return "Auto" }
        let tokens = [
            nonEmpty(version.resolution)?.uppercased(),
            version.hdr == true ? "HDR" : nil,
        ].compactMap { $0 }
        return tokens.isEmpty ? "Auto" : tokens.joined(separator: " · ")
    }

    static func versionDetailLabel(_ version: FileVersion) -> String {
        let tokens = [
            nonEmpty(normalizedVideoCodec(version.codecVideo)),
            nonEmpty(version.container)?.uppercased(),
            version.fileSize.map(formatFileSize),
        ].compactMap { $0 }
        return tokens.joined(separator: " · ")
    }

    static func versionPrimaryText(_ version: FileVersion) -> String {
        let tokens = [
            nonEmpty(version.resolution),
            nonEmpty(normalizedVideoCodec(version.codecVideo)),
            version.hdr == true ? "HDR" : nil,
            nonEmpty(normalizedAudioCodec(version.codecAudio)),
        ].compactMap { $0 }
        if !tokens.isEmpty {
            return tokens.joined(separator: " · ")
        }
        if let fileName = normalizedFileName(version.fileName) {
            return fileName
        }
        return "Version \(version.fileId)"
    }

    static func versionSecondaryText(_ version: FileVersion) -> String? {
        let tokens = [
            nonEmpty(versionDetailLabel(version)),
        ].compactMap { $0 }
        return tokens.isEmpty ? nil : tokens.joined(separator: " · ")
    }

    static func currentEdition(
        versions: [FileVersion],
        currentVersion: FileVersion?
    ) -> PlaybackEditions.Edition? {
        PlaybackEditions.edition(forFileId: currentVersion?.fileId, in: versions)
            ?? PlaybackEditions.editions(from: versions).first
    }

    static func audioOptions(
        version: FileVersion?,
        selectedAudioTrackIndex: Int?
    ) -> [AudioOption] {
        guard let version else { return [] }
        let selectedOrdinal = resolvedAudioOrdinal(
            version: version,
            selectedAudioTrackIndex: selectedAudioTrackIndex
        )
        return (version.audioTracks ?? []).enumerated().map { ordinal, track in
            AudioOption(
                ordinal: ordinal,
                title: audioTitle(track, ordinal: ordinal),
                detail: audioDetail(track, ordinal: ordinal, version: version),
                isSelected: selectedOrdinal == ordinal
            )
        }
    }

    static func resolvedAudioOrdinal(
        version: FileVersion?,
        selectedAudioTrackIndex: Int?
    ) -> Int? {
        guard let version,
              let tracks = version.audioTracks,
              !tracks.isEmpty else {
            return nil
        }
        if let selectedAudioTrackIndex, tracks.indices.contains(selectedAudioTrackIndex) {
            return selectedAudioTrackIndex
        }
        if let effective = version.effectiveAudioTrackIndex, tracks.indices.contains(effective) {
            return effective
        }
        if let defaultIndex = tracks.firstIndex(where: { $0.isDefault == true }) {
            return defaultIndex
        }
        return tracks.startIndex
    }

    static func audioValueLabel(
        version: FileVersion?,
        selectedAudioTrackIndex: Int?
    ) -> String {
        guard let version,
              let ordinal = resolvedAudioOrdinal(
                  version: version,
                  selectedAudioTrackIndex: selectedAudioTrackIndex
              ),
              let track = version.audioTracks?[safe: ordinal] else {
            return "Unknown"
        }
        return audioTitle(track, ordinal: ordinal)
    }

    static func audioTitle(_ track: AudioTrack, ordinal: Int) -> String {
        let format = [
            nonEmpty(normalizedAudioCodec(track.codec)),
            compactAudioLayout(track),
        ].compactMap { $0 }.joined(separator: " ")
        let language = languageDisplayName(track.language)

        if let format = nonEmpty(format), let language {
            return "\(format) - \(language)"
        }
        if let format = nonEmpty(format) {
            return format
        }
        if let title = usefulAudioTitle(track.title) {
            return [title, language].compactMap { $0 }.joined(separator: " - ")
        }
        if let language {
            return language
        }
        return "Track \(ordinal + 1)"
    }

    static func audioDetail(_ track: AudioTrack, ordinal: Int, version: FileVersion?) -> String {
        var tokens: [String] = []
        if let title = usefulAudioTitle(track.title) {
            tokens.append(title)
        }
        if track.isDefault == true {
            tokens.append("Default")
        }
        if version?.effectiveAudioTrackIndex == ordinal {
            tokens.append("Preferred")
        }
        return tokens.joined(separator: " · ")
    }

    static func subtitleOptions(
        version: FileVersion?,
        selectedSubtitleTrackIndex: Int?
    ) -> [SubtitleOption] {
        (version?.subtitleTracks ?? []).enumerated().map { ordinal, track in
            let index = track.index
            let isSelectable = index != nil
            return SubtitleOption(
                selectionIndex: index,
                title: subtitleTitle(track, ordinal: ordinal),
                detail: subtitleDetail(track, isSelectable: isSelectable),
                isSelected: index != nil && selectedSubtitleTrackIndex == index,
                isSelectable: isSelectable,
                stableId: "\(ordinal)|\(track.id)"
            )
        }
    }

    static func subtitleValueLabel(
        version: FileVersion?,
        selectedSubtitleTrackIndex: Int?
    ) -> String {
        if selectedSubtitleTrackIndex == nil { return "Auto" }
        if selectedSubtitleTrackIndex == -1 { return "Off" }
        guard let selectedSubtitleTrackIndex,
              let match = (version?.subtitleTracks ?? []).enumerated().first(where: { _, track in
                  track.index == selectedSubtitleTrackIndex
              }) else {
            // An explicit positive selection that doesn't resolve in this
            // version's track list (e.g. the displayed version was re-scoped):
            // a subtitle IS requested, so don't mislabel it as "Auto" (no
            // selection). "On" reflects the active-but-unnamed selection.
            return "On"
        }
        return subtitleTitle(match.element, ordinal: match.offset)
    }

    static func subtitleTitle(_ track: SubtitleTrack, ordinal: Int) -> String {
        let type = subtitleType(track, ordinal: ordinal)
        let language = languageDisplayName(track.language)
        if let type, let language {
            return "\(type) - \(language)"
        }
        if let type {
            return type
        }
        if let language {
            return language
        }
        return "Track \(ordinal + 1)"
    }

    static func subtitleDetail(_ track: SubtitleTrack, isSelectable: Bool) -> String {
        var tokens: [String] = []
        if let codec = normalizedSubtitleCodec(track.codec) {
            tokens.append(codec)
        }
        if track.forced == true {
            tokens.append("Forced")
        }
        if track.isDefault == true {
            tokens.append("Default")
        }
        if track.external == true {
            tokens.append("External")
        }
        if !isSelectable {
            tokens.append("Available in player")
        }
        return tokens.joined(separator: " · ")
    }

    static func normalizedVideoCodec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        if codec.contains("hevc") || codec.contains("h265") { return "HEVC" }
        if codec.contains("av1") { return "AV1" }
        if codec.contains("avc") || codec.contains("h264") { return "H.264" }
        return codec.uppercased()
    }

    static func normalizedAudioCodec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        if codec.contains("eac3") || codec.contains("e-ac-3") || codec.contains("ec-3") {
            return "EAC3"
        }
        if codec.contains("ac3") || codec.contains("ac-3") { return "AC3" }
        if codec.contains("aac") { return "AAC" }
        if codec.contains("mp3") { return "MP3" }
        if codec.contains("truehd") { return "TrueHD" }
        if codec.contains("dts") { return "DTS" }
        if codec.contains("flac") { return "FLAC" }
        return codec.uppercased()
    }

    static func normalizedSubtitleCodec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        if codec == "srt" || codec.contains("subrip") { return "SubRip" }
        if codec == "ass" || codec.contains("ass") { return "ASS" }
        if codec == "ssa" || codec.contains("ssa") { return "SSA" }
        if codec == "vtt" || codec.contains("webvtt") { return "WebVTT" }
        if codec.contains("pgs") || codec.contains("hdmv") { return "PGS" }
        if codec.contains("dvd") || codec.contains("vobsub") { return "VobSub" }
        if codec.contains("mov_text") || codec.contains("tx3g") { return "TX3G" }
        return codec.uppercased()
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    private static func compactAudioLayout(_ track: AudioTrack) -> String? {
        if let layout = nonEmpty(track.channelLayout) {
            let lowered = layout.lowercased()
            if lowered.contains("atmos") { return "Atmos" }
            if lowered.contains("7.1") { return "7.1" }
            if lowered.contains("5.1") { return "5.1" }
            if lowered.contains("stereo") { return "Stereo" }
            return layout
        }
        switch track.channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        case let channels?: return "\(channels)ch"
        case nil: return nil
        }
    }

    private static func subtitleType(_ track: SubtitleTrack, ordinal: Int) -> String? {
        if let title = nonEmpty(track.title) {
            let lowered = title.lowercased()
            if lowered.contains("sdh") || lowered.contains("hearing") {
                return "SDH"
            }
            if lowered.contains("closed caption") || lowered == "cc" {
                return "CC"
            }
            if lowered.contains("forced") {
                return "Forced"
            }
            if !isRedundantSubtitleTitle(title, track: track) {
                return displayTitle(title)
            }
        }
        if track.forced == true {
            return "Forced"
        }
        if let codec = normalizedSubtitleCodec(track.codec) {
            return codec
        }
        return nil
    }

    private static func usefulAudioTitle(_ title: String?) -> String? {
        guard let title = nonEmpty(title) else { return nil }
        let lowered = title.lowercased()
        let technicalTerms = [
            "atsc",
            "a/52",
            "ac-3",
            "e-ac-3",
            "eac3",
            "truehd",
            "dts",
            "aac",
            "flac",
        ]
        if technicalTerms.contains(where: { lowered.contains($0) }) {
            return nil
        }
        return displayTitle(title)
    }

    private static func isRedundantSubtitleTitle(_ title: String, track: SubtitleTrack) -> Bool {
        let lowered = title.lowercased()
        let language = languageDisplayName(track.language)?.lowercased()
        let languageCode = nonEmpty(track.language)?.lowercased()
        if lowered == "subtitle" || lowered == "subtitles" {
            return true
        }
        if let language, lowered == language {
            return true
        }
        if let languageCode, lowered == languageCode {
            return true
        }
        if let codec = normalizedSubtitleCodec(track.codec)?.lowercased(),
           lowered == codec.lowercased() || lowered == track.codec?.lowercased() {
            return true
        }
        return false
    }

    private static func displayTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "sdh": return "SDH"
        case "cc": return "CC"
        case "srt", "subrip": return "SubRip"
        case "webvtt", "vtt": return "WebVTT"
        default: return trimmed
        }
    }

    private static func languageDisplayName(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let primary = normalized.split(separator: "-").first.map(String.init) ?? normalized
        if primary.count > 3 {
            return value.capitalized
        }
        let languageCode = languageCodeAliases[primary] ?? primary
        if let displayName = Locale(identifier: "en_US_POSIX")
            .localizedString(forLanguageCode: languageCode) {
            return displayName.capitalized
        }
        return value.uppercased()
    }

    private static let languageCodeAliases: [String: String] = [
        "ara": "ar",
        "chi": "zh",
        "cze": "cs",
        "dan": "da",
        "deu": "de",
        "dut": "nl",
        "eng": "en",
        "fin": "fi",
        "fra": "fr",
        "fre": "fr",
        "ger": "de",
        "hin": "hi",
        "ita": "it",
        "jpn": "ja",
        "kor": "ko",
        "nld": "nl",
        "nor": "no",
        "pol": "pl",
        "por": "pt",
        "rus": "ru",
        "spa": "es",
        "swe": "sv",
        "zho": "zh",
    ]

    private static func normalizedFileName(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        let name = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        return nonEmpty(name)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
