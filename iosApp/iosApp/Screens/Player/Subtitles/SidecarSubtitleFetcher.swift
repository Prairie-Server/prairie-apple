//
//  SidecarSubtitleFetcher.swift
//  Continuum (iOS + tvOS)
//
//  Fetches server-provided subtitle sidecar URLs (`subtitle_urls[].url`)
//  using the app's auth headers. The Silo server serves either raw
//  ASS (`text/x-ssa`) for ASS/SSA tracks or WebVTT (`text/vtt`) for every
//  other text codec. The fetcher returns the raw body + a detected
//  format; the caller (`SubtitleSession`) decides whether to feed
//  libass directly (ASS) or run the VTT converter first.
//

import Foundation

enum SidecarSubtitleFetchError: Error {
    case invalidResponse
    case statusCode(Int)
    case transport(underlying: Error)
    case emptyBody
}

actor SidecarSubtitleFetcher {

    private let session: URLSession
    private let tokenStore: TokenStore

    init(
        session: URLSession? = nil,
        tokenStore: TokenStore = .shared
    ) {
        self.session = session ?? Self.makeSession()
        self.tokenStore = tokenStore
    }

    /// Auth-gated sidecar fetches must not share `URLSession.shared`'s cache:
    /// the cache is keyed by URL alone, so a response fetched under one
    /// profile can be served to a request under a different profile.
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    /// Fetch a subtitle sidecar. Raises `SidecarSubtitleFetchError` on
    /// network failure, non-2xx response, or empty body. The body is
    /// returned as a `String` — subtitle content is always text.
    func fetch(
        url: URL,
        preferredFormatHint: SubtitleFormat? = nil
    ) async throws -> (content: String, format: SubtitleFormat) {
        let request = await buildRequest(url: url)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SidecarSubtitleFetchError.transport(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SidecarSubtitleFetchError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SidecarSubtitleFetchError.statusCode(http.statusCode)
        }
        guard !data.isEmpty else {
            throw SidecarSubtitleFetchError.emptyBody
        }

        // Subtitle files should be UTF-8. Tolerate occasional stray bytes
        // by falling back to `String(decoding:as:)`, which replaces invalid
        // sequences with U+FFFD rather than failing.
        let content: String
        if let utf8 = String(data: data, encoding: .utf8) {
            content = utf8
        } else {
            content = String(decoding: data, as: UTF8.self)
        }

        let format = detectFormat(
            contentType: http.value(forHTTPHeaderField: "Content-Type"),
            urlHint: url,
            codecHint: preferredFormatHint,
            body: content
        )
        return (content, format)
    }

    // MARK: - Request building

    private func buildRequest(url: URL) async -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Accept header advertises what we can handle. The server ignores
        // it today but it sets the expectation cleanly.
        request.setValue(
            "text/vtt, text/x-ssa, text/plain;q=0.5, */*;q=0.1",
            forHTTPHeaderField: "Accept"
        )

        if let token = await tokenStore.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let profileId = await tokenStore.getProfileId() {
            request.setValue(profileId, forHTTPHeaderField: "X-Profile-Id")
        }
        if let profileToken = await tokenStore.getProfileToken() {
            request.setValue(profileToken, forHTTPHeaderField: "X-Profile-Token")
        }
        return request
    }

    // MARK: - Format detection

    /// Priority: content-type header → URL extension → caller's codec hint
    /// → sniff the first few bytes of the body. Last-resort default is
    /// WebVTT since that's what the server serves for everything except
    /// ASS/SSA.
    private func detectFormat(
        contentType: String?,
        urlHint: URL,
        codecHint: SubtitleFormat?,
        body: String
    ) -> SubtitleFormat {
        if let ct = contentType?.lowercased() {
            if ct.contains("text/x-ssa") || ct.contains("text/x-ass")
                || ct.contains("application/x-ass")
                || ct.contains("application/x-ssa") {
                return .ass
            }
            if ct.contains("text/vtt") || ct.contains("application/x-webvtt") {
                return .vtt
            }
            if ct.contains("application/x-subrip") {
                return .srt
            }
        }

        let ext = urlHint.pathExtension.lowercased()
        switch ext {
        case "ass", "ssa": return .ass
        case "vtt":        return .vtt
        case "srt":        return .srt
        default: break
        }

        if let hint = codecHint { return hint }

        // Body sniff. ASS files start with `[Script Info]`. VTT files
        // start with the `WEBVTT` signature. SRT files start with a cue
        // number (digit) followed by a newline and a timestamp line
        // using `,` millisecond separators.
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[Script Info]") || trimmed.hasPrefix("[ScriptInfo]") {
            return .ass
        }
        if trimmed.hasPrefix("WEBVTT") || trimmed.hasPrefix("\u{FEFF}WEBVTT") {
            return .vtt
        }
        if let firstLine = trimmed.split(separator: "\n").first,
           Int(firstLine.trimmingCharacters(in: .whitespaces)) != nil {
            return .srt
        }

        return .vtt
    }
}
