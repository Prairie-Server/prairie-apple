import Foundation

@Observable
@MainActor
class AdminViewModel {
    var stats: AdminStats?
    var isLoading = false
    var isRefreshing = false
    var error: ErrorState?

    init() {
        if let cached: AdminStats = ResponseCache.shared.get(CacheKey.adminStats) {
            stats = cached
        }
    }

    func loadStats() async {
        if stats == nil {
            isLoading = true
        } else {
            isRefreshing = true
        }
        error = nil
        do {
            let fresh: AdminStats = try await ContinuumAPI.shared.get("/api/v1/admin/stats")
            ResponseCache.shared.set(fresh, for: CacheKey.adminStats)
            stats = fresh
        } catch let err {
            if stats == nil {
                self.error = ErrorState(err)
            }
        }
        isLoading = false
        isRefreshing = false
    }
}
