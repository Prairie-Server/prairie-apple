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

    /// Sections for Home in server order, filtered to non-empty rows.
    /// `featured` sections are intentionally excluded so Apple Home respects
    /// the configured Home rows without rendering a separate hero surface.
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
            try await fetchAndApplySections()
        } catch let err {
            // Don't blow away painted content on a transient failure —
            // surface the error only when there's nothing to show.
            if sections.isEmpty {
                let state = ErrorState(err)
                if state.isTransient {
                    await retryTransientInitialLoad()
                } else {
                    self.error = state
                }
            }
        }

        isLoading = false
        isRefreshing = false
    }

    private func fetchAndApplySections() async throws {
        let response = try await StartupContentPrefetcher.fetchHomeSections()
        sections = response.sections.filter { !$0.items.isEmpty }
        error = nil
    }

    private func retryTransientInitialLoad() async {
        try? await Task.sleep(nanoseconds: 750_000_000)
        guard !Task.isCancelled else { return }

        do {
            try await fetchAndApplySections()
        } catch {
            self.error = ErrorState(error)
        }
    }
}
