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
    /// Programmatic focus kick forwarded to the underlying `MediaRow` — used
    /// when an unrelated view (e.g. the tvOS top menu) hands focus down into
    /// this row rather than the user d-padding into it.
    var focusRequest: Int = 0
    var onMoveUp: (() -> Void)? = nil
    /// tvOS-only: card-focus reports forwarded from `MediaRow` so hosts
    /// can drive the Skyline focus marquee with `(item, row title)`.
    var onItemFocus: ((SectionItem) -> Void)? = nil
    /// Optional poster/square card width forwarded to `MediaRow` —
    /// Skyline's dense landing rows (§5.6) pass 208.
    var cardWidth: CGFloat? = nil
    /// Down at the row boundary — forwarded to `MediaRow` for the section pager.
    var onMoveDown: (() -> Void)? = nil

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

    /// Audiobook covers are square, so rows made entirely of audiobooks
    /// (Continue Listening, audiobook library rails) use 1:1 tiles
    /// instead of stretching the cover into a 2:3 poster.
    private var isAudiobookRow: Bool {
        !section.items.isEmpty && section.items.allSatisfy(\.isAudiobook)
    }

    private var layout: MediaRowLayout {
        if isEpisodeRow { return .thumbnail }
        if isAudiobookRow { return .square }
        return .poster
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
            focusRequest: focusRequest,
            onRemoveFromContinueWatching: isContinueWatching ? { removeFromContinueWatching($0) } : nil,
            onSetWatched: { setWatched($0, played: $1) },
            onMoveUp: onMoveUp,
            onItemFocus: onItemFocus,
            cardWidth: cardWidth,
            onMoveDown: onMoveDown
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
