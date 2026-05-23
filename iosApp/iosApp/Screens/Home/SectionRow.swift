import SwiftUI

/// A single section row on the home screen.
/// Wraps MediaRow and handles "continue watching" progress display.
/// Picks the thumbnail layout for episode-centric sections (Next Up,
/// and Continue Watching when the items are episodes).
struct SectionRow: View {
    let section: ResolvedSection
    let onItemTap: (String) -> Void
    var onSeeAll: (() -> Void)? = nil
    var prefersDefaultFocusOnFirstItem: Bool = false
    var onMoveUp: (() -> Void)? = nil

    private var isContinueWatching: Bool {
        section.sectionType == "continue_watching" || section.sectionType == "in_progress"
    }

    /// True when the section has a dedicated "next up / up next" type,
    /// or when every item in it is an episode (series-centric row).
    private var isEpisodeRow: Bool {
        let t = section.sectionType.lowercased()
        if t.contains("next") || t.contains("up_next") || t.contains("next_up") {
            return true
        }
        // If ANY item is an episode, treat the row as episode-centric so the
        // thumbnails use the 16:9 still instead of a poster.
        if section.items.contains(where: { $0.type.lowercased() == "episode" }) {
            return true
        }
        return false
    }

    private var layout: MediaRowLayout {
        isEpisodeRow ? .thumbnail : .poster
    }

    private var showProgress: Bool {
        isContinueWatching || isEpisodeRow
    }

    var body: some View {
        MediaRow(
            title: section.title,
            items: section.items,
            onItemTap: onItemTap,
            onSeeAll: onSeeAll,
            showProgress: showProgress,
            icon: isContinueWatching ? "play.circle.fill" : nil,
            layout: layout,
            prefersDefaultFocusOnFirstItem: prefersDefaultFocusOnFirstItem,
            onRemoveFromContinueWatching: isContinueWatching ? { removeFromContinueWatching($0) } : nil,
            onSetWatched: { setWatched($0, played: $1) },
            onMoveUp: onMoveUp
        )
    }

    private func removeFromContinueWatching(_ item: SectionItem) {
        guard let progressUpdatedAt = item.progressUpdatedAt else { return }

        Task {
            do {
                try await ContinuumAPI.shared.dismissContinueWatchingItem(
                    contentId: item.contentId,
                    progressUpdatedAt: progressUpdatedAt
                )
                NotificationCenter.default.post(name: .homeSectionsShouldRefresh, object: nil)
            } catch {
                print("[Home] Failed to remove \(item.contentId) from Continue Watching: \(error)")
            }
        }
    }

    private func setWatched(_ item: SectionItem, played: Bool) {
        Task {
            do {
                try await ContinuumAPI.shared.setWatched(contentId: item.contentId, played: played)
                NotificationCenter.default.post(name: .homeSectionsShouldRefresh, object: nil)
            } catch {
                print("[Home] Failed to update watched state for \(item.contentId): \(error)")
            }
        }
    }
}
