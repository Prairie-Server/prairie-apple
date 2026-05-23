import Foundation

struct ApplePlaybackQualityOption: Identifiable, Hashable {
    let id: String
    let label: String
    let resolution: String
    let bitrateKbps: Int
    let isOriginal: Bool
    let isAuto: Bool

    var subtitle: String? {
        if isOriginal {
            return nil
        }
        if isAuto {
            return "Best available, direct-play first"
        }
        return "Maximum bitrate: \(bitrateLabel)"
    }

    var bitrateLabel: String {
        ApplePlaybackQuality.formatBitrate(kbps: bitrateKbps)
    }

    var labelWithBitrate: String {
        guard !isOriginal, !isAuto else { return label }
        return "\(label) (\(bitrateLabel))"
    }
}

enum ApplePlaybackQuality {
    static let autoId = "auto"
    static let originalId = "original"

    static let original = ApplePlaybackQualityOption(
        id: originalId,
        label: "Auto",
        resolution: "",
        bitrateKbps: 0,
        isOriginal: true,
        isAuto: false
    )

    static let auto = ApplePlaybackQualityOption(
        id: autoId,
        label: "Auto",
        resolution: "",
        bitrateKbps: 0,
        isOriginal: false,
        isAuto: true
    )

    static let tiers: [ApplePlaybackQualityOption] = [
        .init(id: "1080p-high", label: "Up to 1080p HD (High)", resolution: "1080p", bitrateKbps: 20_000, isOriginal: false, isAuto: false),
        .init(id: "1080p-medium", label: "Up to 1080p HD (Medium)", resolution: "1080p", bitrateKbps: 12_000, isOriginal: false, isAuto: false),
        .init(id: "1080p", label: "Up to 1080p HD", resolution: "1080p", bitrateKbps: 10_000, isOriginal: false, isAuto: false),
        .init(id: "1080p-8", label: "Up to 1080p HD", resolution: "1080p", bitrateKbps: 8_000, isOriginal: false, isAuto: false),
        .init(id: "720p-high", label: "Up to 720p HD (High)", resolution: "720p", bitrateKbps: 4_000, isOriginal: false, isAuto: false),
        .init(id: "720p-medium", label: "Up to 720p HD (Medium)", resolution: "720p", bitrateKbps: 3_000, isOriginal: false, isAuto: false),
        .init(id: "720p", label: "Up to 720p HD", resolution: "720p", bitrateKbps: 2_000, isOriginal: false, isAuto: false),
        .init(id: "480p", label: "Up to 480p", resolution: "480p", bitrateKbps: 1_500, isOriginal: false, isAuto: false),
        .init(id: "328p", label: "Up to 328p", resolution: "328p", bitrateKbps: 700, isOriginal: false, isAuto: false),
    ]

    static let settingsOptions: [ApplePlaybackQualityOption] = [auto] + tiers

    static func normalizeStoredId(_ raw: String?) -> String {
        let value = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch value {
        case "", autoId, originalId, "2160p", "4k", "uhd":
            return autoId
        case "420p":
            return "328p"
        default:
            if settingsOptions.contains(where: { $0.id == value }) {
                return value
            }
            return autoId
        }
    }

    static func displayName(for raw: String) -> String {
        let id = normalizeStoredId(raw)
        return settingsOptions.first(where: { $0.id == id })?.label ?? id
    }

    static func displayNameWithBitrate(for raw: String) -> String {
        let id = normalizeStoredId(raw)
        return settingsOptions.first(where: { $0.id == id })?.labelWithBitrate ?? id
    }

    static func playbackOptions(for _: FileVersion?) -> [ApplePlaybackQualityOption] {
        settingsOptions
    }

    static func resolvedRequestOption(
        preferredQualityId: String?,
        selectedVersion: FileVersion,
        delivery: PlaybackDeliveryStrategy
    ) -> ApplePlaybackQualityOption {
        let id = normalizeStoredId(preferredQualityId)
        if id == autoId {
            return delivery == .transcode ? auto : original
        }
        return playbackOptions(for: selectedVersion).first(where: { $0.id == id })
            ?? (delivery == .transcode ? auto : original)
    }

    static func activeQualityId(
        requestedQualityId: String?,
        selectedVersion: FileVersion,
        delivery: PlaybackDeliveryStrategy
    ) -> String {
        let id = normalizeStoredId(requestedQualityId)
        if id == autoId {
            return autoId
        }
        if playbackOptions(for: selectedVersion).contains(where: { $0.id == id }) {
            return id
        }
        return autoId
    }

    static func shouldForceTranscode(
        preferredQualityId: String?,
        selectedVersion: FileVersion
    ) -> Bool {
        let id = normalizeStoredId(preferredQualityId)
        guard id != autoId else { return false }
        guard let option = settingsOptions.first(where: { $0.id == id && !$0.isOriginal && !$0.isAuto }) else {
            return false
        }
        return exceedsBitrateCap(selectedVersion, option: option)
            || exceedsResolutionCap(selectedVersion, option: option)
    }

    static func targetResolution(
        for option: ApplePlaybackQualityOption,
        selectedVersion: FileVersion
    ) -> String {
        guard !option.isOriginal, !option.isAuto else { return "" }
        guard let targetHeight = height(for: option.resolution),
              let sourceHeight = height(for: selectedVersion.resolution) else {
            return ""
        }
        return sourceHeight > targetHeight ? option.resolution : ""
    }

    static func targetBitrateKbps(
        for option: ApplePlaybackQualityOption,
        selectedVersion: FileVersion
    ) -> Int {
        guard !option.isOriginal, !option.isAuto else { return 0 }
        guard let sourceBitrateKbps = sourceBitrateKbps(for: selectedVersion) else {
            return option.bitrateKbps
        }
        return min(sourceBitrateKbps, option.bitrateKbps)
    }

    static func formatBitrate(kbps: Int) -> String {
        if kbps >= 1000 {
            let mbps = Double(kbps) / 1000.0
            if mbps.rounded(.towardZero) == mbps {
                return "\(Int(mbps)) Mbps"
            }
            return String(format: "%.1f Mbps", mbps)
        }
        return "\(kbps) kbps"
    }

    private static func height(for value: String?) -> Int? {
        guard let value = value?.lowercased() else { return nil }
        if value.contains("2160") || value.contains("4k") { return 2160 }
        if value.contains("1080") { return 1080 }
        if value.contains("720") { return 720 }
        if value.contains("480") { return 480 }
        if value.contains("420") { return 420 }
        if value.contains("328") { return 328 }
        return nil
    }

    private static func exceedsBitrateCap(
        _ version: FileVersion,
        option: ApplePlaybackQualityOption
    ) -> Bool {
        guard let sourceBitrateKbps = sourceBitrateKbps(for: version) else {
            return true
        }
        return sourceBitrateKbps > option.bitrateKbps
    }

    private static func exceedsResolutionCap(
        _ version: FileVersion,
        option: ApplePlaybackQualityOption
    ) -> Bool {
        guard let sourceHeight = height(for: version.resolution),
              let targetHeight = height(for: option.resolution) else {
            return false
        }
        return sourceHeight > targetHeight
    }

    private static func sourceBitrateKbps(for version: FileVersion) -> Int? {
        guard let bitrate = version.bitrate, bitrate > 0 else { return nil }
        return bitrate
    }

}
