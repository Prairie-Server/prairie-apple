#if !os(tvOS)
import Foundation

/// Pure formatting helpers shared between the phone movie / season /
/// episode detail views. Mirrors the small private helpers on the
/// tvOS detail views — kept in one place so the Movie + Season +
/// Episode pages all label versions identically.
enum PhoneVersionFormatting {

    static func versionPrimaryText(_ version: FileVersion) -> String {
        let parts = [
            version.resolution,
            normalizedVideoCodec(version.codecVideo),
            version.hdr == true ? "HDR" : nil,
            normalizedAudioCodec(version.codecAudio),
        ]
        .compactMap(nonEmpty)
        if !parts.isEmpty {
            return parts.joined(separator: " \u{00B7} ")
        }
        return versionFallbackTitle(
            fileId: version.fileId,
            fileName: version.fileName,
            codec: normalizedVideoCodec(version.codecVideo),
            container: version.container
        )
    }

    static func versionMenuLabel(_ version: FileVersion?) -> String? {
        guard let version else { return nil }
        let parts = [
            version.resolution,
            version.hdr == true ? "HDR" : nil,
        ]
        .compactMap(nonEmpty)
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }
        return compactFallbackLabel(
            codec: normalizedVideoCodec(version.codecVideo),
            container: version.container,
            fileName: version.fileName,
            fallback: "Version \(version.fileId)"
        )
    }

    static func versionSecondaryText(_ version: FileVersion) -> String {
        let details = [
            version.container?.uppercased(),
            version.fileSize.map(formatFileSize),
        ]
        .compactMap { $0 }
        return details.isEmpty ? "Playable" : details.joined(separator: " \u{00B7} ")
    }

    // MARK: - Episode files (season-detail next-up picker)

    static func episodeFileTitle(_ file: EpisodeFile) -> String {
        let parts = [
            file.resolution,
            normalizedVideoCodec(file.codecVideo),
            file.hdr == true ? "HDR" : nil,
            file.audioChannels.map { "\($0)ch" },
        ]
        .compactMap(nonEmpty)
        if !parts.isEmpty {
            return parts.joined(separator: " \u{00B7} ")
        }
        return compactFallbackLabel(
            codec: normalizedVideoCodec(file.codecVideo),
            container: file.container,
            fileName: nil,
            fallback: "Version \(file.fileId)"
        )
    }

    static func episodeFileDetail(_ file: EpisodeFile) -> String? {
        let parts = [
            file.container?.uppercased(),
            file.fileSize.map(formatFileSize),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    static func episodeFileLabel(_ file: EpisodeFile?) -> String {
        guard let file else { return "Auto" }
        let parts = [
            file.resolution,
            file.hdr == true ? "HDR" : nil,
        ].compactMap(nonEmpty)
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }
        return compactFallbackLabel(
            codec: normalizedVideoCodec(file.codecVideo),
            container: file.container,
            fileName: nil,
            fallback: "Version \(file.fileId)"
        )
    }

    // MARK: - Codec / container normalization

    static func normalizedVideoCodec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        if codec.contains("hevc") || codec.contains("h265") { return "HEVC" }
        if codec.contains("av1") { return "AV1" }
        if codec.contains("avc") || codec.contains("h264") { return "H.264" }
        return codec.uppercased()
    }

    static func normalizedAudioCodec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        if codec.contains("eac3") || codec.contains("ec-3") { return "EAC3" }
        if codec.contains("ac3") || codec.contains("ac-3") { return "AC3" }
        if codec.contains("aac") { return "AAC" }
        if codec.contains("mp3") { return "MP3" }
        return codec.uppercased()
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }

    private static func versionFallbackTitle(
        fileId: Int,
        fileName: String?,
        codec: String?,
        container: String?
    ) -> String {
        if let fileName = normalizedFileName(fileName) {
            return fileName
        }
        return compactFallbackLabel(
            codec: codec,
            container: container,
            fileName: nil,
            fallback: "Version \(fileId)"
        )
    }

    private static func compactFallbackLabel(
        codec: String?,
        container: String?,
        fileName: String?,
        fallback: String
    ) -> String {
        if let codec = nonEmpty(codec) {
            return codec
        }
        if let container = nonEmpty(container)?.uppercased() {
            return container
        }
        if let fileName = normalizedFileName(fileName) {
            return fileName
        }
        return fallback
    }

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
#endif
