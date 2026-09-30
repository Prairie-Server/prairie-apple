import Foundation

/// One-time raster decode capability for Prairie Apple clients.
/// Current deployment targets always support AVIF + WebP + PNG.
enum ImageFormats {
    static let avif = "avif"
    static let webp = "webp"
    static let png = "png"

    /// Ordered best-first format tokens for this process.
    static var preferred: [String] = [avif, webp, png]

    /// Request header the server reads to pick AVIF / WebP / PNG artwork.
    static let headerField = "X-Prairie-Image-Formats"

    /// Value for the `X-Prairie-Image-Formats` request header.
    static var headerValue: String { preferred.joined(separator: ",") }

    /// Stamp the raster preference on an outgoing Prairie request.
    static func apply(to request: inout URLRequest) {
        request.setValue(headerValue, forHTTPHeaderField: headerField)
    }

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
