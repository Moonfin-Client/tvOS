import Foundation
import Combine

enum GenreSortOption: String, CaseIterable {
    case nameAsc
    case nameDesc
    case mostItems
    case leastItems
    case random

    var displayName: String {
        switch self {
        case .nameAsc: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        case .mostItems: return "Most Items"
        case .leastItems: return "Least Items"
        case .random: return "Random"
        }
    }
}

struct GenreItem: Identifiable, Equatable {
    let id: String
    let name: String
    let backdropUrl: String?
    let itemCount: Int
    let parentId: String?
    let serverId: String?
}

@MainActor
final class GenreBrowseViewModel: ObservableObject {
    @Published private(set) var genres: [GenreItem] = []
    @Published private(set) var isLoading = true
    @Published private(set) var totalGenres = 0
    @Published private(set) var focusedGenre: GenreItem?
    @Published private(set) var title = "Genres"
    @Published var currentSort: GenreSortOption = .nameAsc

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private let parentId: String?
    let includeType: String?
    private var allGenres: [GenreItem] = []
    private var hasLoaded = false
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainer, parentId: String? = nil, includeType: String? = nil) {
        self.container = container
        self.parentId = parentId
        self.includeType = includeType

        backgroundService.configure(preferences: container.userPreferences)
        backgroundService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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
            if let parentId {
                await loadLibraryName(client: client, parentId: parentId)
            }
            await loadGenres(client: client)
        }
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
        if let parentId, !parentId.isEmpty {
            parts.append("from '\(title)'")
        } else {
            parts.append("from all libraries")
        }
        parts.append("sorted by \(currentSort.displayName)")
        return parts.joined(separator: " ")
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
                        await self?.createGenreItem(genre: genre, client: client)
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

    private func createGenreItem(genre: ServerItem, client: MediaServerClient) async -> GenreItem? {
        do {
            let resolvedTypes: [ItemType]
            if let includeType, let t = ItemType(rawValue: includeType) {
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

            var backdropUrl: String?
            if let item = result.items.first,
               let tags = item.backdropImageTags, !tags.isEmpty {
                backdropUrl = client.imageApi.getItemImageUrl(
                    itemId: item.id, imageType: .backdrop,
                    maxWidth: 780, maxHeight: nil, tag: tags.first
                )
            }

            return GenreItem(
                id: genre.id,
                name: genre.name,
                backdropUrl: backdropUrl,
                itemCount: count,
                parentId: parentId,
                serverId: nil
            )
        } catch {
            return nil
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
