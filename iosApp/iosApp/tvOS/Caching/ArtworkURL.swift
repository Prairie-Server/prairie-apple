import Foundation

/// Artwork URL helpers mirroring prairie-server `internal/artworkkey` / web `artworkUrl.ts`.
/// Canonical cache keys stay `.webp`; clients pick the best sibling immediately using
/// `ImageFormats` instead of AVIF-first trial-and-error.
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

    /// Ordered load candidates using the process `ImageFormats` preference list.
    static func candidates(for urlString: String) -> [String] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let byFormat: [String: String] = [
            ImageFormats.webp: trimmed,
            ImageFormats.avif: webPAVIFSibling(of: trimmed) ?? "",
            ImageFormats.png: webPPNGSibling(of: trimmed) ?? "",
        ]
        var out: [String] = []
        var seen = Set<String>()
        for format in ImageFormats.preferred {
            let url = byFormat[format]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !url.isEmpty, seen.insert(url).inserted else { continue }
            out.append(url)
        }
        if out.isEmpty { out.append(trimmed) }
        return out
    }

    /// Best immediate artwork URL for this device without codec probing.
    static func preferred(_ urlString: String) -> String {
        candidates(for: urlString).first ?? urlString
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
