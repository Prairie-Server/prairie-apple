import SwiftUI

func libraryCollectionAccessibilityLabel(_ collection: LibraryCollection) -> String {
    let type = collection.kind == .userCollections
        ? "User collection"
        : collection.collectionType?.capitalized ?? "Collection"
    let count = if let itemCount = collection.itemCount {
        "\(itemCount) item\(itemCount == 1 ? "" : "s")"
    } else {
        "Smart"
    }
    return [collection.name, type, count].joined(separator: ", ")
}

/// List of user-created collections, grouped into named buckets +
/// "Ungrouped". Mirrors the web app's `Collections` page.
struct CollectionsView: View {
    @State private var viewModel = CollectionsViewModel()
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if !viewModel.collections.isEmpty || !viewModel.groups.isEmpty {
                sectionedList
            } else if let error = viewModel.error {
                ErrorView(state: error, onRetry: { Task { await viewModel.loadCollections() } })
            } else if viewModel.isLoading {
                Color.clear
            } else {
                EmptyStateView(
                    icon: "square.stack",
                    title: "No collections",
                    subtitle: "Create a collection to organize your media"
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if case .unknown(let message) = viewModel.groupSupport {
                groupSupportNotice(message)
            }
        }
        .prairiePageBackground()
        .navigationTitle("Collections")
        .prairieNavigationTitleDisplayMode(.large)
        .toolbar {
            #if os(macOS)
            if viewModel.canManageGroups {
                ToolbarItem {
                    Button {
                        viewModel.pendingGroupAction = .create
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.prairiePrimary)
                    }
                }
            }
            ToolbarItem {
                Button {
                    viewModel.showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.prairiePrimary)
                }
            }
            #else
            if viewModel.canManageGroups {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.pendingGroupAction = .create
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.prairiePrimary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.prairiePrimary)
                }
            }
            #endif
        }
        .sheet(isPresented: $viewModel.showCreateSheet) {
            createSheet
        }
        .sheet(item: $viewModel.pendingGroupAction) { action in
            GroupActionSheet(action: action, viewModel: viewModel)
        }
        .task {
            await viewModel.loadCollections()
        }
        .refreshable {
            await viewModel.loadCollections()
        }
    }

    // MARK: - Sectioned list

    private var sectionedList: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section {
                    if section.collections.isEmpty {
                        Text("Drop collections here to add them to this group.")
                            .font(.prairieSmall)
                            .foregroundColor(.prairieSecondaryText)
                            .listRowBackground(Color.prairieSurface)
                    } else {
                        ForEach(section.collections) { collection in
                            collectionRow(collection)
                                .listRowBackground(Color.prairieSurface)
                                #if !os(tvOS)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.pendingGroupAction = .deleteCollection(collection)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    if viewModel.canManageGroups {
                                        Button {
                                            viewModel.pendingGroupAction = .move(collection)
                                        } label: {
                                            Label("Move", systemImage: "folder")
                                        }
                                        .tint(.prairiePrimary)
                                    }
                                }
                                #endif
                        }
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        #if os(tvOS) || os(macOS)
        .listStyle(.plain)
        #else
        .listStyle(.insetGrouped)
        #endif
        .prairieScrollContentBackgroundHidden()
    }

    @ViewBuilder
    private func sectionHeader(_ section: UserCollectionSection) -> some View {
        HStack {
            Text(section.name)
                .font(.prairieCaption)
                .foregroundColor(.prairieSecondaryText)
            Spacer()
            if viewModel.canManageGroups, let groupId = section.groupId,
               let group = viewModel.groups.first(where: { $0.id == groupId }) {
                Menu {
                    Button {
                        viewModel.pendingGroupAction = .rename(group)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        viewModel.pendingGroupAction = .delete(group)
                    } label: {
                        Label("Delete group", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.prairieSecondaryText)
                }
            }
        }
    }

    /// The capability read failed: groups can't be managed until it is
    /// retried, but nothing concludes they are unsupported.
    private func groupSupportNotice(_ message: String) -> some View {
        HStack(spacing: PrairieTheme.padding) {
            Text(message)
                .font(.prairieCaption)
                .foregroundColor(.prairieSecondaryText)
            Spacer()
            Button("Retry") {
                Task { await viewModel.retryGroupSupport() }
            }
            .foregroundColor(.prairiePrimary)
        }
        .padding(.horizontal, PrairieTheme.padding)
        .padding(.vertical, 8)
        .background(Color.prairieSurface)
    }

    private func collectionRow(_ collection: UserCollection) -> some View {
        Button {
            router.navigate(to: .collectionDetail(collectionId: collection.id))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(.prairieBody)
                        .foregroundColor(.prairieOnSurface)

                    Text(rowSubtitle(for: collection))
                        .font(.prairieCaption)
                        .foregroundColor(.prairieSecondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.prairieCaption)
                    .foregroundColor(.prairieSecondaryText)
            }
            .padding(.vertical, 4)
        }
    }

    private func rowSubtitle(for collection: UserCollection) -> String {
        let kind = (collection.collectionType ?? "custom").capitalized
        if let count = collection.itemCount, count > 0 {
            return "\(kind) · \(count) item\(count == 1 ? "" : "s")"
        }
        return kind
    }

    // MARK: - Create Sheet

    private var createSheet: some View {
        NavigationStack {
            VStack(spacing: PrairieTheme.largePadding) {
                TextField("Collection name", text: $viewModel.newCollectionName)
                    .textFieldStyle(PrairieTextFieldStyle())

                if let message = viewModel.createError {
                    Text(message)
                        .font(.prairieCaption)
                        .foregroundColor(.prairieError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Create Collection", systemImage: "plus") {
                    Task { await viewModel.createCollection() }
                }
                .prairiePrimaryButton()
                .disabled(viewModel.isSaving
                    || viewModel.newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding(PrairieTheme.padding)
            .prairieSheetBackground()
            .navigationTitle("New Collection")
            .prairieNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        viewModel.showCreateSheet = false
                    }
                    .foregroundColor(.prairieSecondaryText)
                }
            }
            .prairieNavigationBarSurfaceBackground()
        }
        .presentationDetents([.medium])
    }
}

/// Modal for create-group / rename-group / delete-group / move-collection /
/// delete-collection. Edits of an existing item read its current version when
/// the sheet opens and send that version; after a conflict or an unknown
/// outcome the sheet offers Reload instead of resending.
private struct GroupActionSheet: View {
    let action: CollectionsViewModel.GroupAction
    let viewModel: CollectionsViewModel

    @State private var name: String = ""
    @State private var pendingMoveTarget: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .prairieSheetBackground()
                .prairieNavigationTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }
                            .foregroundColor(.prairieSecondaryText)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmLabel, systemImage: confirmSystemImage) { Task { await confirm() } }
                            .foregroundColor(.prairiePrimary)
                            .disabled(!canConfirm)
                    }
                }
                .prairieNavigationBarSurfaceBackground()
        }
        .presentationDetents([.medium])
        .task {
            await viewModel.loadEditor()
        }
        .onAppear {
            switch action {
            case .rename(let g): name = g.name
            case .move(let c): pendingMoveTarget = c.groupId
            default: break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch action {
        case .create:
            nameForm(title: "New group", prompt: "Group name")
        case .rename(let group):
            nameForm(title: "Rename “\(group.name)”", prompt: "Group name")
        case .delete(let group):
            VStack(spacing: PrairieTheme.padding) {
                Text("Delete “\(group.name)”?")
                    .font(.prairieTitle)
                    .foregroundStyle(Color.prairieOnSurface)
                Text("Collections in this group will move to Ungrouped. This cannot be undone.")
                    .font(.prairieBody)
                    .foregroundStyle(Color.prairieSecondaryText)
                    .multilineTextAlignment(.center)
                errorBanner
                Spacer()
            }
            .padding(PrairieTheme.padding)
            .navigationTitle("Delete group")
        case .deleteCollection(let collection):
            VStack(spacing: PrairieTheme.padding) {
                Text("Delete “\(collection.name)”?")
                    .font(.prairieTitle)
                    .foregroundStyle(Color.prairieOnSurface)
                Text("This cannot be undone.")
                    .font(.prairieBody)
                    .foregroundStyle(Color.prairieSecondaryText)
                    .multilineTextAlignment(.center)
                errorBanner
                Spacer()
            }
            .padding(PrairieTheme.padding)
            .navigationTitle("Delete collection")
        case .move(let collection):
            VStack(spacing: 0) {
                List {
                    Section("Move “\(collection.name)” to") {
                        Button {
                            pendingMoveTarget = nil
                        } label: {
                            moveOptionRow(label: "Ungrouped", selected: pendingMoveTarget == nil)
                        }
                        .listRowBackground(Color.prairieSurface)
                        ForEach(viewModel.groups) { group in
                            Button {
                                pendingMoveTarget = group.id
                            } label: {
                                moveOptionRow(label: group.name, selected: pendingMoveTarget == group.id)
                            }
                            .listRowBackground(Color.prairieSurface)
                        }
                    }
                }
                #if os(tvOS) || os(macOS)
                .listStyle(.plain)
                #else
                .listStyle(.insetGrouped)
                #endif
                .prairieScrollContentBackgroundHidden()
                errorBanner
                    .padding(.horizontal, PrairieTheme.padding)
                    .padding(.bottom, PrairieTheme.padding)
            }
            .navigationTitle("Move collection")
        }
    }

    private func nameForm(title: String, prompt: String) -> some View {
        VStack(spacing: PrairieTheme.largePadding) {
            TextField(prompt, text: $name)
                .textFieldStyle(PrairieTextFieldStyle())
            errorBanner
            Spacer()
        }
        .padding(PrairieTheme.padding)
        .navigationTitle(title)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = viewModel.groupError {
            Text(message)
                .font(.prairieCaption)
                .foregroundColor(.prairieError)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if viewModel.editorNeedsReload {
            Button("Reload") {
                Task { await viewModel.loadEditor() }
            }
            .foregroundColor(.prairiePrimary)
            .disabled(viewModel.isLoadingEditor)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moveOptionRow(label: String, selected: Bool) -> some View {
        HStack {
            Text(label)
                .font(.prairieBody)
                .foregroundColor(.prairieOnSurface)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundColor(.prairiePrimary)
            }
        }
    }

    private var confirmLabel: String {
        switch action {
        case .create: return "Create"
        case .rename: return "Save"
        case .delete, .deleteCollection: return "Delete"
        case .move: return "Move"
        }
    }

    private var confirmSystemImage: String {
        switch action {
        case .create: return "plus"
        case .rename: return "square.and.arrow.down"
        case .delete, .deleteCollection: return "trash"
        case .move: return "folder"
        }
    }

    private var canConfirm: Bool {
        guard viewModel.canSubmitGroupAction else { return false }
        switch action {
        case .create, .rename:
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .delete, .move, .deleteCollection:
            return true
        }
    }

    private func confirm() async {
        switch action {
        case .create:
            await viewModel.createGroup(name: name)
        case .rename(let group):
            await viewModel.renameGroup(id: group.id, name: name)
        case .delete(let group):
            await viewModel.deleteGroup(id: group.id)
        case .move(let collection):
            await viewModel.moveCollection(id: collection.id, toGroupId: pendingMoveTarget)
        case .deleteCollection(let collection):
            await viewModel.deleteCollection(id: collection.id)
        }
        // The view model clears `pendingGroupAction` only on success;
        // keep the sheet open on error so the failure and any Reload
        // action show in the sheet, with the draft intact.
        if viewModel.pendingGroupAction == nil {
            dismiss()
        }
    }
}

@Observable
@MainActor
private class LibraryCollectionsViewModel {
    /// Ordered render sections — either named groups from the server or
    /// a single anonymous section synthesized from a flat response.
    var sections: [LibraryCollectionSection] = []
    var isLoading = false
    var isRefreshing = false
    var error: ErrorState?

    var isEmpty: Bool { sections.allSatisfy { $0.collections.isEmpty } }

    func loadCollections(libraryId: Int) async {
        let key = "library:\(libraryId):collections"
        if sections.isEmpty,
           let cached: [LibraryCollectionSection] = ResponseCache.shared.get(key) {
            sections = cached
        }
        if sections.isEmpty {
            isLoading = true
        } else {
            isRefreshing = true
        }
        error = nil

        do {
            let response = try await PrairieAPI.shared.libraryCollections(libraryId: libraryId)
            let resolved = response.resolvedSections
            ResponseCache.shared.set(resolved, for: key)
            sections = resolved
        } catch let err {
            if sections.isEmpty {
                error = ErrorState(err)
            }
        }

        isLoading = false
        isRefreshing = false
    }
}

struct LibraryCollectionsView: View {
    let libraryId: Int

    @State private var viewModel = LibraryCollectionsViewModel()
    @State private var uiCustomization = UICustomizationPreferences.shared
    @State private var gridWidth: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var hSize

    private var columns: [GridItem] {
        if usesThreeColumnPhoneLayout {
            return Array(
                repeating: GridItem(.flexible(), spacing: 12),
                count: 3
            )
        }
        return AdaptiveColumns.posters(
            for: hSize,
            posterSize: uiCustomization.cardPresentation.posterSize
        )
    }

    var body: some View {
        Group {
            if !viewModel.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PrairieTheme.padding) {
                        ForEach(viewModel.sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(PrairieTheme.padding)
                    .padding(.bottom, PrairieTheme.largePadding)
                }
                .reportsPageChromeScroll()
            } else if let error = viewModel.error {
                ErrorView(state: error, onRetry: { Task { await viewModel.loadCollections(libraryId: libraryId) } })
            } else if viewModel.isLoading {
                Color.clear
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up.fill",
                    title: "No collections yet",
                    subtitle: "Create library collections in the web app to feature curated shelves here."
                )
            }
        }
        .prairiePageBackground()
        .task(id: libraryId) {
            await viewModel.loadCollections(libraryId: libraryId)
        }
        .refreshable {
            await viewModel.loadCollections(libraryId: libraryId)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: LibraryCollectionSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !section.name.isEmpty {
                Text(section.name)
                    .font(.prairieTitle)
                    .foregroundColor(.prairieOnSurface)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(section.collections) { collection in
                    NavigationLink(
                        value: Route.libraryCollection(
                            libraryId: libraryId,
                            collectionId: collection.id,
                            title: collection.name,
                            kind: collection.kind
                        )
                    ) {
                        LibraryCollectionCard(
                            collection: collection,
                            cardWidthOverride: libraryCollectionCardWidthOverride
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(libraryCollectionAccessibilityLabel(collection))
                }
            }
            #if os(iOS)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                guard abs(width - gridWidth) >= 0.5 else { return }
                gridWidth = width
            }
            #endif
        }
    }

    private var usesThreeColumnPhoneLayout: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var libraryCollectionCardWidthOverride: CGFloat? {
        guard usesThreeColumnPhoneLayout else { return nil }
        return AdaptiveColumns.fittedPosterWidth(
            containerWidth: gridWidth,
            columnCount: 3,
            spacing: 12
        )
    }
}

private struct LibraryCollectionCard: View {
    let collection: LibraryCollection
    let cardWidthOverride: CGFloat?
    @State private var uiCustomization = UICustomizationPreferences.shared

    private var cardWidth: CGFloat {
        cardWidthOverride
            ?? (PrairieTheme.posterCardWidth * uiCustomization.cardPresentation.posterSize.scale)
    }
    private var cardHeight: CGFloat {
        cardWidth * (PrairieTheme.posterCardHeight / PrairieTheme.posterCardWidth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                poster

                Text(countLabel)
                    .font(.prairieSmall)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(8)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: PrairieTheme.smallCornerRadius))

            if uiCustomization.cardPresentation.caption.showsTitle {
                Text(collection.name)
                    .font(.prairieCaption)
                    .foregroundStyle(Color.prairieOnSurface)
                    .lineLimit(2, reservesSpace: true)
            }

            if uiCustomization.cardPresentation.caption.showsMetadata {
                Text(typeLabel)
                    .font(.prairieSmall)
                    .foregroundStyle(Color.prairieSecondaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: cardWidth, alignment: .leading)
    }

    @ViewBuilder
    private var poster: some View {
        if let posterUrl = collection.posterUrl, !posterUrl.isEmpty {
            AsyncImageView(
                url: posterUrl,
                thumbhash: collection.posterThumbhash,
                targetSize: CGSize(width: cardWidth, height: cardHeight),
                contentMode: .fill
            )
            .frame(width: cardWidth, height: cardHeight)
            .clipped()
        } else {
            ZStack {
                Color.prairieSurfaceVariant
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.prairieSecondaryText)
            }
            .frame(width: cardWidth, height: cardHeight)
        }
    }

    private var countLabel: String {
        if let itemCount = collection.itemCount {
            return "\(itemCount)"
        }
        return "Smart"
    }

    private var typeLabel: String {
        if collection.kind == .userCollections {
            return "User collection"
        }
        return collection.collectionType?.capitalized ?? "Collection"
    }
}

struct LibraryCollectionDetailView: View {
    let libraryId: Int
    let collectionId: String
    let title: String?
    let kind: LibraryCollectionKind?

    @State private var items: [BrowseItem] = []
    @State private var isLoading = false
    @State private var error: ErrorState?
    @State private var hasMore = true
    @State private var totalItems: Int?
    /// Where the next page starts; `nil` before the live first page and
    /// after the last one. A cached first page has no continuation.
    @State private var continuation: APIv2CatalogContinuation?

    @Environment(AppRouter.self) private var router

    private let pageSize = 60

    var body: some View {
        Group {
            if !items.isEmpty {
                content
            } else if let error {
                ErrorView(state: error, onRetry: { Task { await loadItems(reset: true) } })
            } else if isLoading {
                Color.clear
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up.fill",
                    title: "Collection is empty",
                    subtitle: "This collection does not have any items yet."
                )
            }
        }
        .prairiePageBackground()
        .environment(\.browseLibraryId, libraryId)
        .navigationTitle(title ?? "Collection")
        .prairieNavigationTitleDisplayMode(.large)
        .task(id: "\(libraryId)-\(collectionId)") {
            await loadItems(reset: true)
        }
        .refreshable {
            await loadItems(reset: true)
        }
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: PrairieTheme.padding) {
                Text(countLabel)
                    .font(.prairieCaption)
                    .foregroundColor(.prairieSecondaryText)

                CatalogGrid(
                    items: items,
                    isLoading: isLoading,
                    hasMore: hasMore,
                    forcesThreeColumnsOnPhone: true,
                    onItemTap: { item in
                        router.navigate(to: .itemDetail(browseItem: item, libraryId: libraryId))
                    },
                    onLoadMore: {
                        Task { await loadMoreIfNeeded() }
                    }
                )
            }
            .padding(.horizontal, PrairieTheme.padding)
            .padding(.top, PrairieTheme.smallPadding)
            .padding(.bottom, PrairieTheme.largePadding)
        }
    }

    private var countLabel: String {
        if let totalItems, !hasMore {
            return "\(totalItems) item\(totalItems == 1 ? "" : "s")"
        }
        let suffix = hasMore ? "+" : ""
        return "\(items.count)\(suffix) item\(items.count == 1 && !hasMore ? "" : "s")"
    }

    private func loadMoreIfNeeded() async {
        guard hasMore, !isLoading else { return }
        await loadItems(reset: false)
    }

    private func loadItems(reset: Bool) async {
        guard !isLoading else { return }
        let cacheKey = CacheKey.catalogCollectionItems(collectionId)
        if reset {
            // Surface the cached first page instantly so the grid doesn't
            // blank out while the network call runs.
            if items.isEmpty,
               let cached: CatalogResponse = ResponseCache.shared.get(cacheKey) {
                items = cached.items
                hasMore = cached.hasMore ?? false
                totalItems = cached.totalExact == false ? nil : cached.total
            } else if items.isEmpty {
                hasMore = true
                totalItems = nil
            }
        }
        guard reset || hasMore else { return }

        isLoading = true
        error = nil

        // A reset, or a load-more over a cached first page, starts over from
        // the first page and replaces the grid instead of appending to it.
        let nextPage = reset ? nil : continuation

        do {
            let page: CatalogListPage
            if let nextPage {
                page = try await PrairieAPI.shared.nextCatalogPage(nextPage)
            } else {
                page = try await PrairieAPI.shared.catalogPage(.collectionItems(
                    kind: kind ?? .regular, collectionId: collectionId, limit: pageSize
                ))
            }
            if nextPage != nil, !page.startsOver {
                items.append(contentsOf: page.response.items)
            } else {
                items = page.response.items
                ResponseCache.shared.set(page.response, for: cacheKey)
            }
            totalItems = page.response.totalExact == false ? nil : page.response.total
            continuation = page.continuation
            hasMore = page.continuation != nil
        } catch let err {
            if items.isEmpty {
                error = ErrorState(err)
            }
        }

        isLoading = false
    }
}
