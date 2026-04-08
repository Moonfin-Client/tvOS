import Foundation
import Combine

struct SearchResultGroup: Identifiable {
    let id: String
    let title: String
    let items: [ServerItem]
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var resultGroups: [SearchResultGroup] = []
    @Published private(set) var seerrResults: [SeerrDiscoverItemDto] = []
    @Published private(set) var isSearching = false
    @Published private(set) var focusedItem: ServerItem?
    @Published var query = ""

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private var searchTask: Task<Void, Never>?
    private var backdropDebounceTask: Task<Void, Never>?
    private var previousQuery = ""
    private var cancellables = Set<AnyCancellable>()

    private static let debounceDuration: UInt64 = 600_000_000

    private static let searchGroups: [(id: String, title: String, types: [ItemType])] = [
        ("movies", "Movies", [.movie]),
        ("series", "Series", [.series]),
        ("episodes", "Episodes", [.episode]),
        ("videos", "Videos", [.video]),
        ("programs", "Programs", [.liveTvProgram]),
        ("channels", "Channels", [.liveTvChannel]),
        ("playlists", "Playlists", [.playlist]),
        ("artists", "Artists", [.musicArtist]),
        ("albums", "Albums", [.musicAlbum]),
        ("songs", "Songs", [.audio]),
        ("photoAlbums", "Photo Albums", [.photoAlbum]),
        ("photos", "Photos", [.photo]),
        ("collections", "Collections", [.boxSet]),
        ("people", "People", [.person]),
    ]

    init(container: AppContainer, initialQuery: String? = nil) {
        self.container = container

        backgroundService.configure(preferences: container.userPreferences)
        backgroundService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        if let initialQuery, !initialQuery.isEmpty {
            query = initialQuery
        }
    }

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    private var imageApi: ServerImageApi? { client?.imageApi }

    func searchDebounced() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != previousQuery else { return }
        previousQuery = trimmed

        searchTask?.cancel()

        guard !trimmed.isEmpty else {
            resultGroups = []
            seerrResults = []
            isSearching = false
            backgroundService.clearBackground()
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: Self.debounceDuration)
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmed)
        }
    }

    func searchImmediately() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        previousQuery = trimmed

        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            await performSearch(query: trimmed)
        }
    }

    func setFocusedItem(_ item: ServerItem) {
        focusedItem = item
        backdropDebounceTask?.cancel()
        backdropDebounceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard let self, self.focusedItem?.id == item.id else { return }
            if let url = self.imageUrl(for: item, type: .backdrop, maxWidth: 1920) {
                self.backgroundService.setBackground(url: url)
            }
        }
    }

    func posterUrl(for item: ServerItem) -> String? {
        guard let imageApi else { return nil }
        let tag = item.imageTags?["Primary"]
        return imageApi.getItemImageUrl(
            itemId: item.id, imageType: .primary,
            maxWidth: 300, maxHeight: nil, tag: tag
        )
    }

    func subtitle(for item: ServerItem) -> String {
        switch item.type {
        case .episode:
            if let series = item.seriesName {
                let ep = formatEpisode(item)
                return ep.isEmpty ? series : "\(series) · \(ep)"
            }
            return formatEpisode(item)
        case .audio, .musicAlbum:
            return item.artists?.joined(separator: ", ") ?? item.albumArtist ?? ""
        case .musicArtist:
            return item.albumCount.map { "\($0) albums" } ?? "Artist"
        case .playlist:
            return item.childCount.map { "\($0) items" } ?? "Playlist"
        case .person:
            return ""
        default:
            return item.productionYear.map { String($0) } ?? ""
        }
    }

    private func formatEpisode(_ item: ServerItem) -> String {
        guard let season = item.parentIndexNumber, let episode = item.indexNumber else { return "" }
        return "S\(season):E\(episode)"
    }

    private func performSearch(query: String) async {
        guard let client else {
            isSearching = false
            return
        }

        let results = await withTaskGroup(of: SearchResultGroup.self) { group in
            for spec in Self.searchGroups {
                group.addTask {
                    let items = await self.searchItemTypes(
                        client: client, query: query,
                        types: spec.types
                    )
                    return SearchResultGroup(
                        id: spec.id, title: spec.title,
                        items: items
                    )
                }
            }

            var collected: [SearchResultGroup] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        guard !Task.isCancelled else { return }

        let orderedIds = Self.searchGroups.map(\.id)
        let sorted = results.sorted { a, b in
            (orderedIds.firstIndex(of: a.id) ?? 0) < (orderedIds.firstIndex(of: b.id) ?? 0)
        }

        let parental = container.parentalControlsRepository
        let filtered = sorted.map { group in
            SearchResultGroup(id: group.id, title: group.title, items: parental.filterItems(group.items))
        }

        resultGroups = filtered.filter { !$0.items.isEmpty }
        isSearching = false

        if container.seerrRepository.isAvailable.value {
            if let page = try? await container.seerrRepository.search(query: query, mediaType: nil, limit: 20, offset: 0) {
                seerrResults = page.results.filter { !$0.isBlacklisted }
            }
        }
    }

    private func searchItemTypes(
        client: MediaServerClient, query: String, types: [ItemType]
    ) async -> [ServerItem] {
        do {
            let request: GetItemsRequest
            if types == [.video] {
                request = GetItemsRequest(
                    recursive: true,
                    excludeItemTypes: [.movie, .episode, .liveTvChannel],
                    searchTerm: query,
                    limit: 24,
                    mediaTypes: [.video],
                    imageTypeLimit: 1,
                    enableTotalRecordCount: false
                )
            } else {
                request = GetItemsRequest(
                    recursive: true,
                    includeItemTypes: types,
                    searchTerm: query,
                    limit: 24,
                    imageTypeLimit: 1,
                    enableTotalRecordCount: false
                )
            }
            let result = try await client.itemsApi.getItems(request: request)
            return result.items
        } catch {
            return []
        }
    }

    private func imageUrl(for item: ServerItem, type: ImageType, maxWidth: Int) -> String? {
        guard let imageApi else { return nil }
        if type == .backdrop {
            if let tags = item.backdropImageTags, let tag = tags.first {
                return imageApi.getItemImageUrl(
                    itemId: item.id, imageType: .backdrop,
                    maxWidth: maxWidth, maxHeight: nil, tag: tag
                )
            }
            if let parentTags = item.parentBackdropImageTags,
               let parentId = item.parentBackdropItemId, !parentTags.isEmpty {
                return imageApi.getItemImageUrl(
                    itemId: parentId, imageType: .backdrop,
                    maxWidth: maxWidth, maxHeight: nil, tag: parentTags.first
                )
            }
        }
        let tag = item.imageTags?["Primary"]
        return imageApi.getItemImageUrl(
            itemId: item.id, imageType: .primary,
            maxWidth: maxWidth, maxHeight: nil, tag: tag
        )
    }
}
