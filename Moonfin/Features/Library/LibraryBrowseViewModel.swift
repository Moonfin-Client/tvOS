import SwiftUI
import Combine

struct SortOption: Equatable {
    let name: String
    let sortBy: ItemSortBy
    let sortOrder: SortOrder
}

@MainActor
final class LibraryBrowseViewModel: ObservableObject {
    @Published private(set) var items: [ServerItem] = []
    @Published private(set) var isLoading = true
    @Published private(set) var totalItems = 0
    @Published private(set) var hasMoreItems = false
    @Published private(set) var focusedItem: ServerItem?
    @Published private(set) var libraryName = ""
    @Published private(set) var collectionType: String?
    @Published var currentSort: SortOption
    @Published var filterFavorites: Bool
    @Published var filterUnwatched: Bool
    @Published var startLetter: String?
    @Published var posterSize: PosterSize
    @Published var imageType: ImageDisplayType

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private let parentId: String
    private let serverId: String?
    private let includeTypes: [ItemType]?
    private let genreName: String?
    private let libraryPreferences: LibraryPreferences
    private var currentPage = 0
    private var isLoadingMore = false
    private let pageSize = 100
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var isGenreMode: Bool { genreName != nil }
    var isForcedSquareMode: Bool {
        if let includeTypes, !includeTypes.isEmpty {
            return includeTypes.allSatisfy { type in
                type == .musicAlbum || type == .musicArtist || type == .albumArtist
            }
        }
        return collectionType == "music"
    }

    private var resolvedImageType: ImageDisplayType {
        isForcedSquareMode ? .square : imageType
    }

    private static let defaultFields: [ItemField] = [
        .overview, .primaryImageAspectRatio, .genres, .mediaSources, .providerIds
    ]

    var sortOptions: [SortOption] {
        var options: [SortOption] = [
            SortOption(name: "Name", sortBy: .sortName, sortOrder: .ascending),
            SortOption(name: "Date Added", sortBy: .dateCreated, sortOrder: .descending),
            SortOption(name: "Premiere Date", sortBy: .premiereDate, sortOrder: .descending),
            SortOption(name: "Rating", sortBy: .officialRating, sortOrder: .ascending),
            SortOption(name: "Community Rating", sortBy: .communityRating, sortOrder: .descending),
            SortOption(name: "Critic Rating", sortBy: .criticRating, sortOrder: .descending),
        ]
        if collectionType == "tvshows" {
            options.append(SortOption(name: "Last Played", sortBy: .seriesDatePlayed, sortOrder: .descending))
        } else {
            options.append(SortOption(name: "Last Played", sortBy: .datePlayed, sortOrder: .descending))
        }
        if collectionType == "movies" {
            options.append(SortOption(name: "Runtime", sortBy: .runtime, sortOrder: .ascending))
        }
        return options
    }

    init(
        container: AppContainer,
        parentId: String,
        serverId: String? = nil,
        includeTypes: [ItemType]? = nil,
        genreName: String? = nil
    ) {
        self.container = container
        self.parentId = parentId
        self.serverId = serverId
        self.includeTypes = includeTypes
        self.genreName = genreName

        let prefs = LibraryPreferences(store: container.preferenceStore, libraryId: parentId)
        self.libraryPreferences = prefs
        self.posterSize = prefs.posterSize
        self.imageType = prefs.imageType
        self.filterFavorites = prefs.filterFavoritesOnly
        self.filterUnwatched = prefs.filterUnwatchedOnly

        let savedSortBy = prefs.sortBy
        let savedSortOrder = prefs.sortOrder
        self.currentSort = SortOption(name: "", sortBy: savedSortBy, sortOrder: savedSortOrder)

        backgroundService.configure(preferences: container.userPreferences)
        backgroundService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private var client: MediaServerClient? {
        if let serverId, let uuid = UUID(uuidString: serverId),
           let server = container.serverRepository.storedServers.value.first(where: { $0.id == uuid }) {
            return container.serverClientFactory.client(for: server)
        }
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    var imageApi: ServerImageApi? { client?.imageApi }

    var cardDimensions: (width: CGFloat, height: CGFloat) {
        switch resolvedImageType {
        case .poster:
            switch posterSize {
            case .smallest: return (120, 180)
            case .small: return (150, 225)
            case .medium: return (180, 270)
            case .large: return (220, 330)
            case .xLarge: return (270, 405)
            }
        case .thumb:
            switch posterSize {
            case .smallest: return (200, 112)
            case .small: return (240, 135)
            case .medium: return (280, 158)
            case .large: return (340, 191)
            case .xLarge: return (420, 236)
            }
        case .banner:
            switch posterSize {
            case .smallest: return (360, 62)
            case .small: return (440, 76)
            case .medium: return (520, 90)
            case .large: return (620, 107)
            case .xLarge: return (740, 128)
            }
        case .square:
            switch posterSize {
            case .smallest: return (120, 120)
            case .small: return (150, 150)
            case .medium: return (180, 180)
            case .large: return (220, 220)
            case .xLarge: return (270, 270)
            }
        }
    }

    // MARK: - Actions

    func initialize() {
        if let genreName { libraryName = genreName }
        loadItems()
        if !isGenreMode {
            Task {
                guard let client else { return }
                await loadLibraryInfo(client: client)
            }
        }
    }

    func loadItems() {
        loadTask?.cancel()
        loadTask = Task { await fetchItems(reset: true) }
    }

    func loadMore() {
        guard !isLoadingMore, hasMoreItems else { return }
        Task { await fetchItems(reset: false) }
    }

    func setSortOption(_ option: SortOption) {
        currentSort = option
        savePreferences()
        loadItems()
    }

    func toggleFavorites() {
        filterFavorites.toggle()
        savePreferences()
        loadItems()
    }

    func toggleUnwatched() {
        filterUnwatched.toggle()
        savePreferences()
        loadItems()
    }

    func setStartLetter(_ letter: String?) {
        startLetter = letter
        loadItems()
    }

    func setFocusedItem(_ item: ServerItem) {
        focusedItem = item
        guard let imageApi else { return }
        var urls: [String] = []
        if let tags = item.backdropImageTags, !tags.isEmpty {
            for tag in tags {
                urls.append(imageApi.getItemImageUrl(
                    itemId: item.id, imageType: .backdrop,
                    maxWidth: 1920, maxHeight: nil, tag: tag
                ))
            }
        } else if let pid = item.parentBackdropItemId, let tags = item.parentBackdropImageTags, !tags.isEmpty {
            for tag in tags {
                urls.append(imageApi.getItemImageUrl(
                    itemId: pid, imageType: .backdrop,
                    maxWidth: 1920, maxHeight: nil, tag: tag
                ))
            }
        }
        if !urls.isEmpty { backgroundService.setBackground(urls: urls) }
    }

    func setPosterSize(_ size: PosterSize) {
        posterSize = size
        libraryPreferences.posterSize = size
    }

    func setImageType(_ type: ImageDisplayType) {
        if isForcedSquareMode {
            imageType = .square
            return
        }
        imageType = type
        libraryPreferences.imageType = type
    }

    func imageUrl(for item: ServerItem) -> String? {
        guard let imageApi else { return nil }
        let w = Int(cardDimensions.width * 2)
        switch resolvedImageType {
        case .poster, .square:
            return imageApi.getItemImageUrl(
                itemId: item.id, imageType: .primary,
                maxWidth: w, maxHeight: nil, tag: item.imageTags?["Primary"]
            )
        case .thumb:
            if let tag = item.imageTags?["Thumb"] {
                return imageApi.getItemImageUrl(itemId: item.id, imageType: .thumb, maxWidth: w, maxHeight: nil, tag: tag)
            }
            if let tag = item.backdropImageTags?.first {
                return imageApi.getItemImageUrl(itemId: item.id, imageType: .backdrop, maxWidth: w, maxHeight: nil, tag: tag)
            }
            return imageApi.getItemImageUrl(
                itemId: item.id, imageType: .primary,
                maxWidth: w, maxHeight: nil, tag: item.imageTags?["Primary"]
            )
        case .banner:
            if let tag = item.imageTags?["Banner"] {
                return imageApi.getItemImageUrl(itemId: item.id, imageType: .banner, maxWidth: w, maxHeight: nil, tag: tag)
            }
            return imageApi.getItemImageUrl(
                itemId: item.id, imageType: .primary,
                maxWidth: w, maxHeight: nil, tag: item.imageTags?["Primary"]
            )
        }
    }

    func buildMetadata(for item: ServerItem) -> String {
        var parts: [String] = []
        if let year = item.productionYear, year > 0 { parts.append(String(year)) }
        if let rating = item.officialRating, !rating.isEmpty { parts.append(rating) }
        if let ticks = item.runTimeTicks, ticks > 0 { parts.append(RuntimeFormatter.format(ticks: ticks)) }
        if let cr = item.communityRating { parts.append(" \(String(format: "%.1f", cr))") }
        return parts.joined(separator: "  ")
    }

    func buildStatusText() -> String {
        var parts = ["Showing"]
        if !filterFavorites && !filterUnwatched {
            parts.append("All items")
        } else {
            if filterUnwatched { parts.append("Unwatched") }
            if filterFavorites { parts.append("Favorites") }
        }
        if let letter = startLetter { parts.append("starting with \(letter)") }
        parts.append("from '\(libraryName)'")
        let sortName = sortOptions.first(where: { $0.sortBy == currentSort.sortBy })?.name ?? "Name"
        parts.append("sorted by \(sortName)")
        return parts.joined(separator: " ")
    }

    // MARK: - Data Loading

    private func fetchItems(reset: Bool) async {
        guard let client else { isLoading = false; return }
        if isLoadingMore && !reset { return }

        if reset {
            currentPage = 0
            isLoading = true
            items = []
        }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            var filters: [ItemFilter] = []
            if filterFavorites { filters.append(.isFavorite) }
            if filterUnwatched { filters.append(.isUnplayed) }

            if !isGenreMode,
               let includeTypes,
               includeTypes.count == 1,
               includeTypes[0] == .musicArtist || includeTypes[0] == .albumArtist {
                let result = try await fetchArtistItems(
                    client: client,
                    includeType: includeTypes[0],
                    filters: filters,
                    startIndex: currentPage * pageSize
                )

                let fetchedItems = container.parentalControlsRepository.filterItems(result.items)
                let allItems = reset ? fetchedItems : items + fetchedItems
                currentPage += 1

                self.items = allItems
                self.totalItems = result.totalRecordCount
                self.hasMoreItems = allItems.count < result.totalRecordCount
                self.isLoading = false
                return
            }

            let resolvedIncludeTypes: [ItemType]?
            let resolvedExcludeTypes: [ItemType]?
            let recursive: Bool

            if isGenreMode {
                resolvedIncludeTypes = includeTypes ?? [.movie, .series]
                resolvedExcludeTypes = nil
                recursive = true
            } else {
                switch collectionType {
                case "movies":
                    resolvedIncludeTypes = [.movie]
                    resolvedExcludeTypes = [.boxSet]
                    recursive = true
                case "tvshows":
                    resolvedIncludeTypes = [.series]
                    resolvedExcludeTypes = nil
                    recursive = true
                case "music":
                    resolvedIncludeTypes = includeTypes ?? [.musicAlbum]
                    resolvedExcludeTypes = nil
                    recursive = true
                default:
                    resolvedIncludeTypes = includeTypes
                    resolvedExcludeTypes = nil
                    recursive = includeTypes != nil
                }
            }

            let request = GetItemsRequest(
                parentId: parentId,
                recursive: recursive,
                includeItemTypes: resolvedIncludeTypes,
                excludeItemTypes: resolvedExcludeTypes,
                sortBy: [currentSort.sortBy, .sortName],
                sortOrder: currentSort.sortOrder,
                filters: filters.isEmpty ? nil : filters,
                fields: Self.defaultFields,
                limit: pageSize,
                startIndex: currentPage * pageSize,
                genres: genreName.map { [$0] },
                enableImages: true,
                imageTypeLimit: 1,
                enableUserData: true,
                nameStartsWith: startLetter,
                collapseBoxSetItems: false,
                enableTotalRecordCount: true
            )

            let result = try await client.itemsApi.getItems(request: request)
            let playlistFilteredItems = applyPlaylistExclusionLogic(to: result.items)
            let fetchedItems = container.parentalControlsRepository.filterItems(playlistFilteredItems)
            let allItems = reset ? fetchedItems : items + fetchedItems
            currentPage += 1

            self.items = allItems
            self.totalItems = result.totalRecordCount
            self.hasMoreItems = allItems.count < result.totalRecordCount
            self.isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func fetchArtistItems(
        client: MediaServerClient,
        includeType: ItemType,
        filters: [ItemFilter],
        startIndex: Int
    ) async throws -> ItemsResult {
        let path = includeType == .albumArtist ? "/Artists/AlbumArtists" : "/Artists"
        let query = buildQuery([
            ("UserId", client.userId),
            ("ParentId", parentId),
            ("Recursive", "true"),
            ("SortOrder", currentSort.sortOrder.rawValue),
            ("SortBy", [currentSort.sortBy, .sortName].map(\.rawValue).joined(separator: ",")),
            ("Fields", Self.defaultFields.map(\.rawValue).joined(separator: ",")),
            ("Filters", filters.isEmpty ? nil : filters.map(\.rawValue).joined(separator: ",")),
            ("EnableImages", "true"),
            ("ImageTypeLimit", "1"),
            ("EnableUserData", "true"),
            ("NameStartsWith", startLetter),
            ("StartIndex", String(startIndex)),
            ("Limit", String(pageSize)),
        ])
        return try await client.httpClient.request(path, queryItems: query)
    }

    private func loadLibraryInfo(client: MediaServerClient) async {
        guard libraryName.isEmpty else { return }
        do {
            let parentItem = try await client.userLibraryApi.getItem(itemId: parentId)
            libraryName = parentItem.name
            collectionType = parentItem.collectionType
        } catch {}
    }

    private func applyPlaylistExclusionLogic(to sourceItems: [ServerItem]) -> [ServerItem] {
        guard includeTypes == [.playlist] else { return sourceItems }

        if collectionType == "music" {
            return sourceItems.filter { $0.mediaType != .video }
        }

        if collectionType == "playlists" {
            return sourceItems.filter { $0.mediaType != .audio }
        }

        return sourceItems
    }

    private func savePreferences() {
        libraryPreferences.filterFavoritesOnly = filterFavorites
        libraryPreferences.filterUnwatchedOnly = filterUnwatched
        libraryPreferences.sortBy = currentSort.sortBy
        libraryPreferences.sortOrder = currentSort.sortOrder
    }
}
