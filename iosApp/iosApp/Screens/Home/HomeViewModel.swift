import Foundation

@Observable
@MainActor
class HomeViewModel {
    var sections: [ResolvedSection] = []
    /// True only on the very first load when no cached data exists.
    /// Returning visits paint cached sections instantly and use
    /// `isRefreshing` for the silent background fetch.
    var isLoading = false
    /// In-flight refresh signal — drives the inline indicator while
    /// painted content stays on screen.
    var isRefreshing = false
    var error: ErrorState?

    /// Featured section (first section if marked as featured).
    var featuredSection: ResolvedSection? {
        sections.first(where: { $0.isFeatured })
    }

    /// Non-featured sections for the vertical list (filtered to non-empty).
    var regularSections: [ResolvedSection] {
        sections.filter { !$0.isFeatured && !$0.items.isEmpty }
    }

    init() {
        // Hydrate from the shared cache so the first render after a
        // navigation paints last-known data without any network wait.
        if let cached: SectionsResponse = ResponseCache.shared.get(CacheKey.homeSections) {
            sections = cached.sections.filter { !$0.items.isEmpty }
        }
    }

    func loadSections() async {
        if sections.isEmpty {
            isLoading = true
        } else {
            isRefreshing = true
        }
        error = nil

        do {
            let response: SectionsResponse = try await ContinuumAPI.shared.get(
                "/api/v1/home/sections"
            )
            ResponseCache.shared.set(response, for: CacheKey.homeSections)
            sections = response.sections.filter { !$0.items.isEmpty }
        } catch let err {
            // Don't blow away painted content on a transient failure —
            // surface the error only when there's nothing to show.
            if sections.isEmpty {
                self.error = ErrorState(err)
            }
        }

        isLoading = false
        isRefreshing = false
    }
}
