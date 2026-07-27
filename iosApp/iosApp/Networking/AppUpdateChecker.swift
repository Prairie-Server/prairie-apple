import Foundation

/// Marketing semver used for client update checks.
struct AppVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: Bool

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease == rhs.prerelease { return false }
        return lhs.prerelease && !rhs.prerelease
    }

    var displayString: String { "\(major).\(minor).\(patch)" }

    static func parse(_ raw: String?) -> AppVersion? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.lowercased().hasPrefix("v"), text.count > 1 {
            text = String(text.dropFirst())
        }
        let withoutBuild = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? text
        let prerelease = withoutBuild.contains("-")
        let core = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? withoutBuild
        let parts = core.split(separator: ".").map(String.init)
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return nil
        }
        let patch = parts.count >= 3 ? Int(parts[2]) ?? 0 : 0
        return AppVersion(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }
}

enum AppUpdateStatus: Equatable, Sendable {
    case checking
    case upToDate(current: String, latest: String, changelogURL: URL?)
    case updateAvailable(current: String, latest: String, releaseURL: URL?, changelogURL: URL?)
    case unavailable(current: String, reason: String, changelogURL: URL?)

    var statusLabel: String {
        switch self {
        case .checking: return "Checking…"
        case .upToDate: return "Up to date"
        case .updateAvailable: return "Update available"
        case .unavailable(_, let reason, _): return reason
        }
    }

    var latestVersionLabel: String? {
        switch self {
        case .checking, .unavailable: return nil
        case .upToDate(_, let latest, _), .updateAvailable(_, let latest, _, _): return latest
        }
    }

    var changelogURL: URL? {
        switch self {
        case .checking: return nil
        case .upToDate(_, _, let url): return url
        case .updateAvailable(_, _, let release, let changelog): return changelog ?? release
        case .unavailable(_, _, let url): return url
        }
    }

    var releaseURL: URL? {
        if case .updateAvailable(_, _, let release, _) = self { return release }
        return nil
    }
}

enum AppUpdateResolver {
    static func resolve(
        currentVersionName: String,
        latestVersionName: String?,
        releaseURL: URL?,
        changelogURL: URL? = nil
    ) -> AppUpdateStatus {
        let notes = changelogURL ?? releaseURL
        guard let current = AppVersion.parse(currentVersionName) else {
            return .unavailable(current: currentVersionName, reason: "Couldn't check for updates", changelogURL: notes)
        }
        guard let latestRaw = latestVersionName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !latestRaw.isEmpty,
              let latest = AppVersion.parse(latestRaw) else {
            return .unavailable(current: currentVersionName, reason: "Couldn't check for updates", changelogURL: notes)
        }
        let latestDisplay = latest.displayString
        if latest > current {
            return .updateAvailable(
                current: currentVersionName,
                latest: latestDisplay,
                releaseURL: releaseURL,
                changelogURL: notes
            )
        }
        return .upToDate(current: currentVersionName, latest: latestDisplay, changelogURL: notes)
    }
}

enum AppUpdateChecker {
    static let defaultReleasesLatestURL = URL(
        string: "https://api.github.com/repos/Prairie-Server/prairie-apple/releases/latest"
    )!
    static let defaultChangelogURL = URL(
        string: "https://github.com/Prairie-Server/prairie-apple/releases"
    )!

    static func marketingVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static func displayVersionString() -> String {
        let short = marketingVersionString()
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !build.isEmpty,
           build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    static func check(
        currentVersionName: String = marketingVersionString(),
        session: URLSession = .shared,
        releasesLatestURL: URL = defaultReleasesLatestURL
    ) async -> AppUpdateStatus {
        var request = URLRequest(url: releasesLatestURL, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Prairie-Apple", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                return .upToDate(
                    current: currentVersionName,
                    latest: currentVersionName,
                    changelogURL: defaultChangelogURL
                )
            }
            guard (200..<300).contains(status) else {
                return .unavailable(
                    current: currentVersionName,
                    reason: "Couldn't check for updates",
                    changelogURL: defaultChangelogURL
                )
            }
            let release = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
            let releaseURL = release.htmlURL.flatMap(URL.init(string:))
            return AppUpdateResolver.resolve(
                currentVersionName: currentVersionName,
                latestVersionName: release.tagName ?? release.name,
                releaseURL: releaseURL,
                changelogURL: releaseURL ?? defaultChangelogURL
            )
        } catch {
            return .unavailable(
                current: currentVersionName,
                reason: "Couldn't check for updates",
                changelogURL: defaultChangelogURL
            )
        }
    }

    private struct GitHubLatestRelease: Decodable {
        let tagName: String?
        let name: String?
        let htmlURL: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
        }
    }
}
