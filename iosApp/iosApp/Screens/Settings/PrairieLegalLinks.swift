import Foundation

enum PrairieLegalLinks {
    static let privacyPolicy = URL(string: "https://prairieserver.org/privacy/")!
    static let privacyPolicy = URL(string: "https://prairieserver.org/privacy")!
    static let repository = URL(string: "https://github.com/Prairie-Server/prairie-apple")!

    /// The published source archive for this build. Release lanes stamp it as
    /// `PrairieSourceURL`; local builds have none and link the repository.
    static let sourceCode = sourceURL(
        stamped: Bundle.main.object(forInfoDictionaryKey: "PrairieSourceURL") as? String
    )
    /// Accepts only a release asset of this repository, so a malformed or
    /// unexpanded stamp still leads to the right source.
    static func sourceURL(stamped: String?) -> URL {
        guard let stamped,
              let url = URL(string: stamped),
              url.scheme == "https",
              url.host == repository.host,
              url.path.hasPrefix(repository.path + "/releases/download/") else {
            return repository
        }
        return url
    }
}
