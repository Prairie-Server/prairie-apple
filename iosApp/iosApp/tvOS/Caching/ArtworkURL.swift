import Foundation

/// Artwork URL helpers mirroring prairie-server `internal/artworkkey` / web `artworkUrl.ts`.
/// Canonical cache keys stay `.webp`; clients try AVIF → WebP → PNG for older devices.
enum ArtworkURL {
    /// AVIF sibling of a canonical `.webp` URL/path. Non-WebP inputs return `nil`.
    /// Query/fragment are preserved for signed CDN URLs.
    static func webPAVIFSibling(of urlString: String) -> String? {
        webPFormatSibling(of: urlString, ext: "avif")
    }

    /// PNG sibling of a canonical `.webp` URL/path. Non-WebP inputs return `nil`.
    static func webPPNGSibling(of urlString: String) -> String? {
        webPFormatSibling(of: urlString, ext: "png")
    }

    /// Ordered load candidates: AVIF → WebP → PNG when the input is WebP.
    static func candidates(for urlString: String) -> [String] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var out: [String] = []
        if let avif = webPAVIFSibling(of: trimmed) { out.append(avif) }
        out.append(trimmed)
        if let png = webPPNGSibling(of: trimmed) { out.append(png) }
        return out
    }

    /// Prefer the AVIF sibling when one can be derived; otherwise the original URL.
    static func preferred(_ urlString: String) -> String {
        webPAVIFSibling(of: urlString) ?? urlString
    }

    private static func webPFormatSibling(of urlString: String, ext: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("://") {
            guard var components = URLComponents(string: trimmed) else { return nil }
            let path = components.percentEncodedPath
            guard !path.isEmpty, let rewritten = rewriteWebPPath(path, ext: ext) else { return nil }
            components.percentEncodedPath = rewritten
            return components.string
        }

        return rewriteWebPPath(trimmed, ext: ext)
    }

    private static func rewriteWebPPath(_ path: String, ext: String) -> String? {
        let pathExt = (path as NSString).pathExtension
        guard pathExt.lowercased() == "webp" else { return nil }
        let stem = (path as NSString).deletingPathExtension
        return stem + "." + ext
    }
}
