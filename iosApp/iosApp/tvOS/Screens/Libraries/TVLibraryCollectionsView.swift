#if os(tvOS)
import SwiftUI

/// `Collections` pill content of a library tab: a vertical grid of every
/// collection in the scoped library (Skyline §6.3). Pressing a card pushes
/// the existing collection detail screen.
struct TVLibraryCollectionsView: View {
    let library: Library
    /// Focus hand-down token from the shell — claims the first card on
    /// tab entry when this pill is the restored destination.
    var focusRequest: Int = 0
    /// Whether the top menu currently holds focus; deferred entry claims
    /// are dropped while the user is up in the menu.
    var isTopMenuFocused: Bool = false
    /// Boundary hand-up toward the pill row for the first card.
    let onMoveUp: (() -> Void)?

    @State private var collectionSections: [LibraryCollectionSection] = []
    @State private var isLoadingCollections = true

    @State private var hasPendingFocusClaim = false
    @State private var lastShellFocusRequest = 0
    @State private var contentFocusToken = 0

    @Environment(AppRouter.self) private var router
    @Namespace private var collectionsFocusNamespace

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 44, pinnedViews: []) {
                Color.clear
                    .frame(height: ContinuumTheme.Skyline.libraryContentTopInset)

                gridContent
            }
            .padding(.bottom, ContinuumTheme.largePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard collectionSections.isEmpty else { return }
            await loadCollections()
        }
        .onAppear { noteShellFocusRequest(focusRequest) }
        .onChange(of: focusRequest) { _, request in noteShellFocusRequest(request) }
        .onChange(of: collectionSections.isEmpty) { _, isEmpty in
            if !isEmpty, hasPendingFocusClaim {
                claimContentFocusIfReady()
            }
        }
    }

    @ViewBuilder
    private var gridContent: some View {
        if isLoadingCollections && collectionSections.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 300)
        } else if collectionSections.isEmpty {
            EmptyStateView(
                icon: "square.stack",
                title: "No collections yet",
                subtitle: "Collections created on the server will appear here."
            )
            .frame(maxWidth: .infinity, minHeight: 400)
        } else {
            // Only the very first card of the first NON-EMPTY section
            // claims default focus when the tab appears. Skipping empty
            // sections matters: grouped responses can include groups with
            // no collections, and falling back to `collectionSections.first`
            // would leave the Collections pill without an initial focus
            // target on tvOS.
            let focusTarget = collectionSections
                .first(where: { !$0.collections.isEmpty })
            let firstSectionId = focusTarget?.id
            let firstCardId = focusTarget?.collections.first?.id

            VStack(alignment: .leading, spacing: 44) {
                ForEach(collectionSections) { section in
                    VStack(alignment: .leading, spacing: 20) {
                        if !section.name.isEmpty {
                            Text(section.name)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.continuumOnSurface)
                                .padding(.leading, ContinuumTheme.safePadding)
                        }
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 40),
                                count: 6
                            ),
                            alignment: .leading,
                            spacing: 60
                        ) {
                            ForEach(section.collections) { collection in
                                let isFirstOverall =
                                    section.id == firstSectionId && collection.id == firstCardId
                                TVCollectionCard(
                                    collection: collection,
                                    prefersDefaultFocus: isFirstOverall,
                                    defaultFocusNamespace: collectionsFocusNamespace,
                                    focusRequest: isFirstOverall ? contentFocusToken : 0,
                                    onMoveUp: isFirstOverall ? onMoveUp : nil,
                                    action: {
                                        router.navigate(to: .libraryCollection(
                                            libraryId: library.id,
                                            collectionId: collection.id,
                                            title: collection.name,
                                            kind: collection.kind
                                        ))
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, ContinuumTheme.safePadding)
                    }
                }
            }
            .focusScope(collectionsFocusNamespace)
            .focusSection()
        }
    }

    // MARK: - Focus hand-down

    private func noteShellFocusRequest(_ request: Int) {
        guard request > 0, request != lastShellFocusRequest else { return }
        lastShellFocusRequest = request
        claimContentFocusIfReady()
    }

    private func claimContentFocusIfReady() {
        guard collectionSections.contains(where: { !$0.collections.isEmpty }) else {
            hasPendingFocusClaim = true
            return
        }
        if hasPendingFocusClaim, isTopMenuFocused {
            hasPendingFocusClaim = false
            return
        }
        hasPendingFocusClaim = false
        contentFocusToken += 1
    }

    // MARK: - Data

    private func loadCollections() async {
        isLoadingCollections = true
        do {
            let response = try await ContinuumAPI.shared.libraryCollections(libraryId: library.id)
            collectionSections = response.resolvedSections
        } catch {
            collectionSections = []
        }
        isLoadingCollections = false
    }
}

// MARK: - Collection card

/// Attaches an Up-move handler only when one is supplied, so that cards which
/// should NOT hand focus up (every card except the first) don't intercept and
/// consume the Up command the focus engine needs to move between grid rows.
private struct TVCollectionCardMoveUpHandler: ViewModifier {
    let onMoveUp: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onMoveUp {
            content.onMoveCommand { direction in
                if direction == .up {
                    onMoveUp()
                }
            }
        } else {
            content
        }
    }
}

/// Vertical poster card for a collection. Matches the dimensions and
/// caption grammar of `TVMediaCard` so a collections grid reads as the
/// same visual family as the library's movie/show grid — just with
/// "items" replacing "year" under the title.
private struct TVCollectionCard: View {
    let collection: LibraryCollection
    var prefersDefaultFocus: Bool = false
    var defaultFocusNamespace: Namespace.ID? = nil
    /// Programmatic focus kick: when this becomes non-zero (the Collections
    /// pill was restored on tab entry) focus jumps to this card, since
    /// `prefersDefaultFocus` alone doesn't fire when the scope isn't being
    /// entered by the engine.
    var focusRequest: Int = 0
    /// Supplied only to the first collection card: Up returns focus to the
    /// pill row — the Collections analogue of the Browse layout's first-row
    /// hand-up. Attached to this card alone so Up from lower grid rows still
    /// moves to the row above instead of jumping to the chrome.
    var onMoveUp: (() -> Void)? = nil
    let action: () -> Void

    @FocusState private var isFocused: Bool
    /// Last hand-down token applied, so each token claims focus exactly once.
    /// The card lives in a `LazyVGrid`; without the guard, `onAppear` re-fires
    /// when the first card is recycled back into view on scroll-up and would
    /// yank focus away from the row the user was navigating.
    @State private var lastAppliedFocusRequest = 0

    private let cardWidth: CGFloat = 220
    private var cardHeight: CGFloat { cardWidth * 1.5 } // 2:3 poster ratio

    var body: some View {
        VStack(spacing: 16) {
            collectionButton

            caption
        }
        .frame(width: cardWidth)
        .onAppear { applyFocusRequest(focusRequest) }
        .onChange(of: focusRequest) { _, request in applyFocusRequest(request) }
        .modifier(TVCollectionCardMoveUpHandler(onMoveUp: onMoveUp))
    }

    private func applyFocusRequest(_ request: Int) {
        guard request > 0, request != lastAppliedFocusRequest else { return }
        lastAppliedFocusRequest = request
        isFocused = true
    }

    private var collectionButton: some View {
        Button(action: action) {
            posterImage
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .applyDefaultFocusIfNeeded(prefersDefaultFocus, namespace: defaultFocusNamespace)
    }

    private var posterImage: some View {
        Group {
            if let posterUrl = collection.posterUrl, !posterUrl.isEmpty {
                CachedAsyncImage(
                    url: posterUrl,
                    targetSize: CGSize(width: cardWidth, height: cardHeight),
                    contentMode: .fill
                )
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.55, brightness: 0.45),
                            Color(hue: hue, saturation: 0.35, brightness: 0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
    }

    private var caption: some View {
        VStack(spacing: 4) {
            Text(collection.name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isFocused ? .continuumOnSurface : .continuumOnSurface.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)

            if collection.kind == .userCollections {
                Text("User collection")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.continuumSecondaryText)
            } else if let count = collection.itemCount, count > 0 {
                Text("\(count) \(count == 1 ? "item" : "items")")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.continuumSecondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: cardWidth, alignment: .center)
    }

    private var hue: Double {
        var hasher = Hasher()
        hasher.combine(collection.id)
        let raw = UInt(bitPattern: hasher.finalize())
        return Double(raw % 360) / 360.0
    }
}
#endif
