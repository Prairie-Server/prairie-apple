import Foundation

@MainActor
enum StartupContentPrefetcher {
    private static let maxHomeArtworkURLs = 12
    private static let maxProfileArtworkURLs = 8
    private static let episodeSectionTypes: Set<String> = [
        "continue_watching",
        "in_progress",
        "next_up",
    ]

    private static var profilesTask: Task<[UserProfile], Error>?
    private static var homeSectionsTask: Task<SectionsResponse, Error>?

    static func prefetchProfiles() {
        Task {
            _ = try? await fetchProfiles()
        }
    }

    static func fetchProfiles() async throws -> [UserProfile] {
        let task: Task<[UserProfile], Error>
        if let profilesTask {
            task = profilesTask
        } else {
            task = Task {
                try await AuthService.shared.getProfiles()
            }
            profilesTask = task
        }

        do {
            let profiles = try await task.value
            profilesTask = nil
            ResponseCache.shared.set(profiles, for: CacheKey.profiles)
            prefetchProfileArtwork(for: profiles)
            return profiles
        } catch {
            profilesTask = nil
            throw error
        }
    }

    static func prefetchHomeSections() {
        Task {
            _ = try? await fetchHomeSections()
        }
    }

    static func fetchHomeSections() async throws -> SectionsResponse {
        let task: Task<SectionsResponse, Error>
        if let homeSectionsTask {
            task = homeSectionsTask
        } else {
            task = Task {
                try await ContinuumAPI.shared.homeSections()
            }
            homeSectionsTask = task
        }

        do {
            let response = try await task.value
            homeSectionsTask = nil
            ResponseCache.shared.set(response, for: CacheKey.homeSections)
            prefetchHomeArtwork(for: response)
            return response
        } catch {
            homeSectionsTask = nil
            throw error
        }
    }

    static func prefetchForInitialRoute(_ state: AppRouter.AuthState) {
        switch state {
        case .authenticated:
            prefetchHomeSections()
            Task {
                await OverlayPrefsStore.shared.hydrateIfNeeded()
            }
        case .needsProfile:
            prefetchProfiles()
        case .loading, .needsServerSetup, .needsLogin:
            break
        }
    }

    private static func prefetchHomeArtwork(for response: SectionsResponse) {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ urlString: String?) {
            guard urls.count < maxHomeArtworkURLs,
                  let url = normalizedURL(from: urlString) else {
                return
            }
            let key = url.absoluteString
            guard seen.insert(key).inserted else { return }
            urls.append(url)
        }

        if let featuredItem = response.sections.first(where: \.isFeatured)?.items.first {
            append(featuredItem.backdropUrl ?? featuredItem.posterUrl)
            append(featuredItem.logoUrl)
        }

        for section in response.sections where !section.isFeatured {
            for item in section.items {
                if episodeSectionTypes.contains(section.sectionType) {
                    append(item.backdropUrl ?? item.posterUrl)
                } else {
                    append(item.posterUrl)
                }
                if urls.count >= maxHomeArtworkURLs { break }
            }
            if urls.count >= maxHomeArtworkURLs { break }
        }

        guard !urls.isEmpty else { return }
        PosterImageCache.prefetcher.startPrefetching(with: urls)
    }

    private static func prefetchProfileArtwork(for profiles: [UserProfile]) {
        var urls: [URL] = []
        var seen = Set<String>()

        for profile in profiles {
            guard urls.count < maxProfileArtworkURLs,
                  let avatar = profile.avatarEmoji?.trimmingCharacters(in: .whitespacesAndNewlines),
                  ProfileAvatarResolver.isImage(avatar),
                  let urlString = ProfileAvatarResolver.imageURL(for: avatar),
                  let url = normalizedURL(from: urlString) else {
                continue
            }

            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            urls.append(url)
        }

        guard !urls.isEmpty else { return }
        PosterImageCache.prefetcher.startPrefetching(with: urls)
    }

    private static func normalizedURL(from urlString: String?) -> URL? {
        guard let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme != nil else {
            return nil
        }
        return url
    }
}
