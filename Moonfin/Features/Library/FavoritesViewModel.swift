import Foundation
import Combine

struct FavoriteSection: Identifiable {
    let id: String
    let title: String
    let items: [ServerItem]
}

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published private(set) var sections: [FavoriteSection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var focusedItem: ServerItem?

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainer) {
        self.container = container

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

    private var imageApi: ServerImageApi? { client?.imageApi }

    func initialize() {
        guard !isLoading else { return }
        Task { await loadFavorites() }
    }

    func setFocusedItem(_ item: ServerItem) {
        focusedItem = item
        if let url = imageApi?.itemBackdropUrl(for: item) {
            backgroundService.setBackground(url: url)
        }
    }

    func posterUrl(for item: ServerItem) -> String? {
        imageApi?.itemPosterUrl(for: item)
    }

    func subtitle(for item: ServerItem) -> String {
        switch item.type {
        case .episode:
            if let series = item.seriesName {
                if let s = item.parentIndexNumber, let e = item.indexNumber {
                    return "\(series) · S\(s):E\(e)"
                }
                return series
            }
            return ""
        case .audio, .musicAlbum:
            return item.artists?.joined(separator: ", ") ?? item.albumArtist ?? ""
        case .person:
            return ""
        case .playlist:
            return item.childCount.map { "\($0) items" } ?? ""
        default:
            return item.productionYear.map { String($0) } ?? ""
        }
    }

    private func loadFavorites() async {
        guard let client else { return }
        isLoading = true

        let typeGroups: [(id: String, title: String, types: [ItemType])] = [
            ("people", "Favorite People", [.person]),
            ("movies", "Favorite Movies", [.movie]),
            ("shows", "Favorite Shows", [.series]),
            ("episodes", "Favorite Episodes", [.episode]),
            ("playlists", "Favorite Playlists", [.playlist]),
        ]

        var loadedSections: [FavoriteSection] = []

        await withTaskGroup(of: (Int, FavoriteSection?).self) { group in
            for (index, typeGroup) in typeGroups.enumerated() {
                group.addTask {
                    let request = GetItemsRequest(
                        recursive: true,
                        includeItemTypes: typeGroup.types,
                        sortBy: [.sortName],
                        sortOrder: .ascending,
                        filters: [.isFavorite],
                        imageTypeLimit: 1,
                        enableTotalRecordCount: false
                    )
                    let result = try? await client.itemsApi.getItems(request: request)
                    guard let items = result?.items, !items.isEmpty else { return (index, nil) }
                    return (index, FavoriteSection(id: typeGroup.id, title: typeGroup.title, items: items))
                }
            }
            var indexed: [(Int, FavoriteSection)] = []
            for await (i, section) in group {
                if let section { indexed.append((i, section)) }
            }
            loadedSections = indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }

        sections = loadedSections
        isLoading = false
    }

}

extension ServerImageApi {
    func itemPosterUrl(for item: ServerItem, maxWidth: Int = 300) -> String {
        let tag = item.imageTags?["Primary"]
        return getItemImageUrl(itemId: item.id, imageType: .primary, maxWidth: maxWidth, maxHeight: nil, tag: tag)
    }

    func itemBackdropUrl(for item: ServerItem) -> String {
        if let tags = item.backdropImageTags, let tag = tags.first {
            return getItemImageUrl(itemId: item.id, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: tag)
        }
        if let parentTags = item.parentBackdropImageTags,
           let parentId = item.parentBackdropItemId, !parentTags.isEmpty {
            return getItemImageUrl(itemId: parentId, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: parentTags.first)
        }
        let tag = item.imageTags?["Primary"]
        return getItemImageUrl(itemId: item.id, imageType: .primary, maxWidth: 1920, maxHeight: nil, tag: tag)
    }
}
