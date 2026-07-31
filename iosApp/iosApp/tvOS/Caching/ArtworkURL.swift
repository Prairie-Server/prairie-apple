import Foundation
import CoreGraphics

/// Artwork URL helpers mirroring prairie-server `internal/artworkkey` / web `artworkUrl.ts`.
/// Canonical cache keys stay `.webp`; clients pick the best sibling immediately using
/// `ImageFormats` instead of AVIF-first trial-and-error.
enum ArtworkURL {
    /// Poster width rungs offered by the artwork store, narrowest first.
    static let posterWidths = [200, 300, 500]

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
    /// When `targetWidthPoints` is set, Prairie-signed width variants are rewritten
    /// first (w200/w300 for card-sized posters) before format siblings.
    static func candidates(
        for urlString: String,
        targetWidthPoints: CGFloat? = nil,
        scale: CGFloat = 1
    ) -> [String] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let sized: String
        if let targetWidthPoints,
           let width = preferredPosterWidth(forPixels: targetWidthPoints * scale),
           let rewritten = widthVariant(of: trimmed, width: width) {
            sized = rewritten
        } else {
            sized = trimmed
        }
        let byFormat: [String: String] = [
            ImageFormats.webp: sized,
            ImageFormats.avif: webPAVIFSibling(of: sized) ?? "",
            ImageFormats.png: webPPNGSibling(of: sized) ?? "",
        ]
        var out: [String] = []
        var seen = Set<String>()
        for format in ImageFormats.preferred {
            let url = byFormat[format]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !url.isEmpty, seen.insert(url).inserted else { continue }
            out.append(url)
        }
        if out.isEmpty { out.append(sized) }
        return out
    }

    /// Best immediate artwork URL for this device without codec probing.
    static func preferred(
        _ urlString: String,
        targetWidthPoints: CGFloat? = nil,
        scale: CGFloat = 1
    ) -> String {
        candidates(for: urlString, targetWidthPoints: targetWidthPoints, scale: scale).first
            ?? urlString
    }

    /// Narrowest poster rung that covers `pixelWidth` (ContinuumTheme card sizes).
    static func preferredPosterWidth(forPixels pixelWidth: CGFloat) -> Int? {
        guard pixelWidth.isFinite, pixelWidth > 0 else { return nil }
        for width in posterWidths where CGFloat(width) >= pixelWidth {
            return width
        }
        return posterWidths.last
    }

    /// Rewrites `original` / `wN` path segments to `w{width}` when safe.
    /// Matches web `artworkWidthVariant`: Prairie-signed artwork may rewrite;
    /// third-party signatures and signed `original` masters must not.
    static func widthVariant(of urlString: String, width: Int) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, width > 0 else { return nil }
        if isThirdPartySignedArtworkURL(trimmed) || isSignedOriginalArtworkURL(trimmed) {
            return nil
        }

        if trimmed.contains("://") {
            guard var components = URLComponents(string: trimmed) else { return nil }
            let path = components.percentEncodedPath
            guard !path.isEmpty else { return nil }
            let next = rewritePathWidthVariant(path, width: width)
            guard next != path else { return nil }
            components.percentEncodedPath = next
            return components.string
        }

        let next = rewritePathWidthVariant(trimmed, width: width)
        return next == trimmed ? nil : next
    }

    /// True when rewriting the path would invalidate a third-party signature.
    /// Prairie's own `sig=`+`expires=` artwork signatures are excluded — they
    /// cover the revision, not the exact width key.
    static func isThirdPartySignedArtworkURL(_ objectPath: String) -> Bool {
        if isPrairieSignedArtworkURL(objectPath) { return false }
        return objectPath.range(
            of: #"[?&](X-Amz-Signature|X-Goog-Signature|Signature|sig|verify)="#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func isPrairieSignedArtworkURL(_ objectPath: String) -> Bool {
        guard objectPath.range(of: #"[?&]sig="#, options: .regularExpression) != nil,
              objectPath.range(of: #"[?&]expires="#, options: .regularExpression) != nil else {
            return false
        }
        return pathname(of: objectPath).contains("/artwork/")
    }

    static func isSignedOriginalArtworkURL(_ objectPath: String) -> Bool {
        guard isPrairieSignedArtworkURL(objectPath) else { return false }
        return pathname(of: objectPath).range(
            of: #"/original(?=\.)"#,
            options: .regularExpression
        ) != nil
    }

    private static func pathname(of objectPath: String) -> String {
        if objectPath.contains("://") {
            return URLComponents(string: objectPath)?.percentEncodedPath ?? ""
        }
        return objectPath
    }

    private static func rewritePathWidthVariant(_ path: String, width: Int) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"/(original|w\d+)(?=\.)"#
        ) else {
            return path
        }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.stringByReplacingMatches(
            in: path,
            range: range,
            withTemplate: "/w\(width)"
        )
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
