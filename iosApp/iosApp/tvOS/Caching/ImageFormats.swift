import Foundation

/// One-time raster decode capability for Prairie Apple clients.
/// Current deployment targets always support AVIF + WebP + PNG.
enum ImageFormats {
    static let avif = "avif"
    static let webp = "webp"
    static let png = "png"

    /// Ordered best-first format tokens for this process.
    static var preferred: [String] = [avif, webp, png]

    /// Value for the `X-Prairie-Image-Formats` request header.
    static var headerValue: String { preferred.joined(separator: ",") }

    /// Replace the process-wide preference list (tests / future OS gates).
    static func configure(_ formats: [String]) {
        let next = formats
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0 == avif || $0 == webp || $0 == png }
        var seen = Set<String>()
        let ordered = next.filter { seen.insert($0).inserted }
        guard !ordered.isEmpty else { return }
        preferred = ordered
    }

    static func resetForTests() {
        preferred = [avif, webp, png]
    }
}
