import Foundation
import Combine

private func genreBrowseLocalized(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

enum GenreSortOption: String, CaseIterable {
    case nameAsc
    case nameDesc
    case mostItems
    case leastItems
    case random

    var displayName: String {
        switch self {
        case .nameAsc: return genreBrowseLocalized("genre_sort_name_asc")
        case .nameDesc: return genreBrowseLocalized("genre_sort_name_desc")
        case .mostItems: return genreBrowseLocalized("genre_sort_most_items")
        case .leastItems: return genreBrowseLocalized("genre_sort_least_items")
        case .random: return genreBrowseLocalized("random")
        }
    }
}

struct GenreItem: Identifiable, Equatable {
    let id: String
    let name: String
    let imageUrl: String?
    let backdropUrl: String?
    let itemCount: Int
    let parentId: String?
    let serverId: String?
}

struct GenreLibraryFilterOption: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
final class GenreBrowseViewModel: ObservableObject {
    @Published private(set) var genres: [GenreItem] = []
    @Published private(set) var isLoading = true
    @Published private(set) var totalGenres = 0
    @Published private(set) var focusedGenre: GenreItem?
    @Published private(set) var title = "Genres"
    @Published private(set) var availableLibraries: [GenreLibraryFilterOption] = []
    @Published var currentSort: GenreSortOption = .nameAsc
    @Published var posterSize: PosterSize
    @Published var imageType: ImageDisplayType
    @Published private(set) var selectedLibraryId: String?

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private let baseParentId: String?
    let includeType: String?
    private var allGenres: [GenreItem] = []
    private var hasLoaded = false
    private var cancellables = Set<AnyCancellable>()
    private static let posterSizeDefaultsKey = "genre_browse_poster_size"
    private static let imageTypeDefaultsKey = "genre_browse_image_type"
    private static let libraryDefaultsKey = "genre_browse_library_id"
    private static let supportedImageTypes: [ImageDisplayType] = [.poster, .thumb, .banner]

    private var resolvedParentId: String? {
        baseParentId ?? selectedLibraryId
    }

    init(container: AppContainer, parentId: String? = nil, includeType: String? = nil) {
        self.container = container
        self.baseParentId = parentId
        self.includeType = includeType
        if let parentId, !parentId.isEmpty {
            self.selectedLibraryId = parentId
        } else {
            let storedLibraryId = UserDefaults.standard.string(forKey: Self.libraryDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.selectedLibraryId = (storedLibraryId?.isEmpty == false) ? storedLibraryId : nil
        }
        if let raw = UserDefaults.standard.string(forKey: Self.posterSizeDefaultsKey),
           let saved = PosterSize(rawValue: raw) {
            self.posterSize = saved
        } else {
            self.posterSize = .medium
        }
        if let raw = UserDefaults.standard.string(forKey: Self.imageTypeDefaultsKey),
           let saved = ImageDisplayType(rawValue: raw),
           Self.supportedImageTypes.contains(saved) {
            self.imageType = saved
        } else {
            self.imageType = .thumb
        }

        backgroundService.configure(preferences: container.userPreferences)
        backgroundService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func setPosterSize(_ size: PosterSize) {
        posterSize = size
        UserDefaults.standard.set(size.rawValue, forKey: Self.posterSizeDefaultsKey)
    }

    func setImageType(_ type: ImageDisplayType) {
        guard Self.supportedImageTypes.contains(type), type != imageType else { return }
        imageType = type
        UserDefaults.standard.set(type.rawValue, forKey: Self.imageTypeDefaultsKey)

        guard let client else { return }
        Task { await loadGenres(client: client) }
    }

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    func initialize() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task {
            guard let client else { isLoading = false; return }
            if baseParentId == nil {
                await loadLibraries(client: client)
            }
            if let parentId = resolvedParentId {
                await loadLibraryName(client: client, parentId: parentId)
            } else {
                title = Strings.genres
            }
            await loadGenres(client: client)
        }
    }

    func setLibraryFilter(_ libraryId: String?) {
        guard baseParentId == nil else { return }

        let normalized = libraryId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextLibraryId = (normalized?.isEmpty == false) ? normalized : nil
        guard selectedLibraryId != nextLibraryId else { return }

        selectedLibraryId = nextLibraryId
        if let nextLibraryId {
            UserDefaults.standard.set(nextLibraryId, forKey: Self.libraryDefaultsKey)
            if let libraryName = availableLibraries.first(where: { $0.id == nextLibraryId })?.name {
                title = "\(Strings.genres) — \(libraryName)"
            }
        } else {
            UserDefaults.standard.removeObject(forKey: Self.libraryDefaultsKey)
            title = Strings.genres
        }

        guard let client else { return }
        Task { await loadGenres(client: client) }
    }

    func setSortOption(_ option: GenreSortOption) {
        currentSort = option
        applySortAndFilter()
    }

    func setFocusedGenre(_ genre: GenreItem) {
        focusedGenre = genre
        if let url = genre.backdropUrl {
            backgroundService.setBackground(url: url)
        }
    }

    func buildStatusText() -> String {
        var parts = ["Showing", "\(totalGenres) genres"]
        if let parentId = resolvedParentId, !parentId.isEmpty {
            parts.append("from '\(title)'")
        } else {
            parts.append("from all libraries")
        }
        parts.append("sorted by \(currentSort.displayName)")
        return parts.joined(separator: " ")
    }

    private func loadLibraries(client: MediaServerClient) async {
        let userId = client.userId ?? ""
        guard !userId.isEmpty else {
            availableLibraries = []
            return
        }

        do {
            let views = try await client.userViewsApi.getUserViews(userId: userId)
            availableLibraries = views
                .map { GenreLibraryFilterOption(id: $0.id, name: $0.name) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if let selectedLibraryId,
               !availableLibraries.contains(where: { $0.id == selectedLibraryId }) {
                self.selectedLibraryId = nil
                UserDefaults.standard.removeObject(forKey: Self.libraryDefaultsKey)
            }
        } catch {
            availableLibraries = []
        }
    }

    private func loadLibraryName(client: MediaServerClient, parentId: String) async {
        guard !parentId.isEmpty else { return }
        do {
            let item = try await client.userLibraryApi.getItem(itemId: parentId)
            title = "Genres — \(item.name)"
        } catch {}
    }

    private func loadGenres(client: MediaServerClient) async {
        isLoading = true
        let parentId = resolvedParentId

        do {
            let userId = client.userId ?? ""
            let query = buildQuery([
                ("UserId", userId),
                ("ParentId", parentId),
                ("SortBy", "SortName"),
                ("SortOrder", "Ascending"),
            ])
            let result: ItemsResult = try await client.httpClient.request("/Genres", queryItems: query)
            let genreBaseItems = result.items

            allGenres = await withTaskGroup(of: GenreItem?.self) { group in
                for genre in genreBaseItems {
                    group.addTask { [weak self] in
                        await self?.createGenreItem(genre: genre, client: client, parentId: parentId)
                    }
                }
                var items: [GenreItem] = []
                for await item in group {
                    if let item { items.append(item) }
                }
                return items
            }

            applySortAndFilter()
        } catch {
            isLoading = false
        }
    }

    private func createGenreItem(genre: ServerItem, client: MediaServerClient, parentId: String?) async -> GenreItem? {
        do {
            let resolvedTypes: [ItemType]
            if let includeType, let t = resolveIncludeType(includeType) {
                resolvedTypes = [t]
            } else {
                resolvedTypes = [.movie, .series]
            }

            let request = GetItemsRequest(
                parentId: parentId,
                recursive: true,
                includeItemTypes: resolvedTypes,
                sortBy: [.random],
                limit: 1,
                genres: [genre.name],
                enableImages: true,
                imageTypeLimit: 1,
                enableTotalRecordCount: true
            )
            let result = try await client.itemsApi.getItems(request: request)
            let count = result.totalRecordCount
            guard count > 0 else { return nil }

            var imageUrl: String?
            var backdropUrl: String?
            if let item = result.items.first {
                if let backdropTag = item.backdropImageTags?.first {
                    backdropUrl = client.imageApi.getItemImageUrl(
                        itemId: item.id,
                        imageType: .backdrop,
                        maxWidth: 780,
                        maxHeight: 780,
                        tag: backdropTag
                    )
                }
                imageUrl = genreImageUrl(for: item, client: client, fallbackBackdropUrl: backdropUrl)
            }

            return GenreItem(
                id: genre.id,
                name: genre.name,
                imageUrl: imageUrl,
                backdropUrl: backdropUrl,
                itemCount: count,
                parentId: parentId,
                serverId: nil
            )
        } catch {
            return nil
        }
    }

    private func resolveIncludeType(_ value: String) -> ItemType? {
        ItemType.allCases.first { candidate in
            candidate.rawValue.caseInsensitiveCompare(value) == .orderedSame
                || candidate.apiValue.caseInsensitiveCompare(value) == .orderedSame
        }
    }

    private func genreImageUrl(for item: ServerItem, client: MediaServerClient, fallbackBackdropUrl: String?) -> String? {
        let primaryTag = item.imageTags?["Primary"]
        let thumbTag = item.imageTags?["Thumb"]
        let bannerTag = item.imageTags?["Banner"]

        switch imageType {
        case .poster:
            if let primaryTag {
                return client.imageApi.getItemImageUrl(
                    itemId: item.id,
                    imageType: .primary,
                    maxWidth: 480,
                    maxHeight: 720,
                    tag: primaryTag
                )
            }
            return fallbackBackdropUrl

        case .thumb:
            if let thumbTag {
                return client.imageApi.getItemImageUrl(
                    itemId: item.id,
                    imageType: .thumb,
                    maxWidth: 780,
                    maxHeight: 440,
                    tag: thumbTag
                )
            }
            return fallbackBackdropUrl

        case .banner:
            if let bannerTag {
                return client.imageApi.getItemImageUrl(
                    itemId: item.id,
                    imageType: .banner,
                    maxWidth: 780,
                    maxHeight: 440,
                    tag: bannerTag
                )
            }
            return fallbackBackdropUrl

        case .square:
            return primaryTag.flatMap { tag in
                client.imageApi.getItemImageUrl(
                    itemId: item.id,
                    imageType: .primary,
                    maxWidth: 480,
                    maxHeight: 480,
                    tag: tag
                )
            } ?? fallbackBackdropUrl
        }
    }

    private func applySortAndFilter() {
        let sorted: [GenreItem]
        switch currentSort {
        case .nameAsc: sorted = allGenres.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc: sorted = allGenres.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .mostItems: sorted = allGenres.sorted { $0.itemCount > $1.itemCount }
        case .leastItems: sorted = allGenres.sorted { $0.itemCount < $1.itemCount }
        case .random: sorted = allGenres.shuffled()
        }
        genres = sorted
        totalGenres = sorted.count
        isLoading = false
    }
}
