#if os(tvOS)
import SwiftUI

/// Body of a Skyline library-type tab (Movies / Series / Music /
/// Audiobooks). Receives the profile's libraries of its type from the
/// shell and renders the active library's landing experience.
///
/// This replaced the old "Libraries is a place" tab: there is no longer a
/// full-screen library picker — the type tab *is* the library.
struct TVLibraryTypeTabView: View {
    let type: TVLibraryTabType
    /// Libraries of `type` visible to this profile, ordered by `sortOrder`.
    let libraries: [Library]
    var focusRequest: Int = 0
    var isTopMenuFocused: Bool = false
    let onTopMenuFocusRequest: (() -> Void)?

    // Skyline Phase 2: scope dropdown — until the anchored dropdown and
    // the merged `All <Type>` scope land, a type with multiple libraries
    // scopes to the first one by sortOrder.
    private var activeLibrary: Library? { libraries.first }

    var body: some View {
        Group {
            if let activeLibrary {
                TVLibraryLandingView(
                    library: activeLibrary,
                    selectedMode: .constant(.recommended),
                    focusRequest: focusRequest,
                    isTopMenuFocused: isTopMenuFocused,
                    onTopMenuFocusRequest: onTopMenuFocusRequest
                )
                // Re-create the landing when the scoped library changes so
                // its section fetches reset cleanly.
                .id(activeLibrary.id)
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "No \(type.title.lowercased()) libraries",
                    subtitle: "Libraries visible to this profile will appear here."
                )
                .padding(.top, TVTopMenuLayout.contentTopInset)
            }
        }
        .continuumBackground()
    }
}
#endif
