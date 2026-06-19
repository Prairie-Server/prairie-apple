#if os(iOS)
import SwiftUI

/// Resolves poster/backdrop artwork for the cast remote from the `contentId`
/// already present in the cast playback state — no wire-protocol field needed.
/// Reuses the same item-detail path (cache → API) the detail screen uses.
@MainActor
@Observable
final class SiloCastArtworkResolver {
    private(set) var posterURL: String?
    private(set) var backdropURL: String?
    private var resolvedContentId: String?

    func resolve(contentId: String?) async {
        guard let contentId, !contentId.isEmpty else {
            posterURL = nil
            backdropURL = nil
            resolvedContentId = nil
            return
        }
        guard contentId != resolvedContentId else { return }

        if let cached: ItemDetail = ResponseCache.shared.get(CacheKey.itemDetail(contentId)) {
            apply(cached, contentId: contentId)
            return
        }

        do {
            let detail = try await ContinuumAPI.shared.itemDetail(contentId: contentId)
            try Task.checkCancellation()
            apply(detail, contentId: contentId)
        } catch {
            // Degrade silently: the remote simply shows the flat background.
        }
    }

    private func apply(_ detail: ItemDetail, contentId: String) {
        posterURL = detail.posterUrl
        backdropURL = detail.backdropUrl
        resolvedContentId = contentId
    }
}

/// Full-bleed blurred-artwork backdrop behind the now-playing content.
/// Falls back to flat OLED black when no artwork is available.
struct SiloCastArtworkBackground: View {
    let urlString: String?

    var body: some View {
        ZStack {
            Color.continuumBackground
            if let urlString, !urlString.isEmpty {
                AsyncImageView(url: urlString, contentMode: .fill, placeholderStyle: .clear)
                    .id(urlString)
                    .blur(radius: 40)
                    .opacity(0.45)
                    .clipped()
            }
            Color.continuumBackground.opacity(0.55)
        }
        .ignoresSafeArea()
    }
}
#endif
