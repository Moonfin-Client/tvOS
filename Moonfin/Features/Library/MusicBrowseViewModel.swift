import Foundation
import Combine

struct MusicRow: Identifiable {
    let id: String
    let title: String
    var items: [ServerItem]
    var isLoading: Bool

    init(id: String, title: String, items: [ServerItem] = [], isLoading: Bool = true) {
        self.id = id
        self.title = title
        self.items = items
        self.isLoading = isLoading
    }
}

@MainActor
final class MusicBrowseViewModel: ObservableObject {
    @Published private(set) var rows: [MusicRow] = []
    @Published private(set) var isLoading = true
    @Published private(set) var libraryName = ""
    @Published private(set) var focusedItem: ServerItem?

    let backgroundService = BackgroundService()

    private let container: AppContainer
    let parentId: String
    private let serverId: String?
    private var hasLoaded = false
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainer, parentId: String, serverId: String? = nil) {
        self.container = container
        self.parentId = parentId
        self.serverId = serverId

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

    func initialize() {
        guard !hasLoaded else { return }
        hasLoaded = true

        rows = [
            MusicRow(id: "latestAudio", title: "Latest Audio"),
            MusicRow(id: "lastPlayed", title: "Last Played"),
            MusicRow(id: "favoriteAlbums", title: "Favorite Albums"),
            MusicRow(id: "playlists", title: "Playlists"),
        ]

        Task {
            guard let client else { isLoading = false; return }
            await loadLibraryName(client: client)
            await loadAllRows(client: client)
            isLoading = false
        }
    }

    func setFocusedItem(_ item: ServerItem) {
        focusedItem = item
        if let url = backdropUrl(for: item) {
            backgroundService.setBackground(url: url)
        }
    }

    func squareImageUrl(for item: ServerItem) -> String? {
        guard let imageApi else { return nil }

        if item.type == .audio, let albumId = item.albumId {
            return imageApi.getItemImageUrl(
                itemId: albumId, imageType: .primary,
                maxWidth: 300, maxHeight: 300, tag: item.albumPrimaryImageTag
            )
        }

        let tag = item.imageTags?["Primary"]
        return imageApi.getItemImageUrl(
            itemId: item.id, imageType: .primary,
            maxWidth: 300, maxHeight: 300, tag: tag
        )
    }

    func subtitle(for item: ServerItem) -> String {
        switch item.type {
        case .audio, .musicAlbum:
            if let artists = item.artists, !artists.isEmpty {
                return artists.joined(separator: ", ")
            }
            if let albumArtist = item.albumArtist {
                return albumArtist
            }
            return ""
        case .playlist:
            if let count = item.childCount {
                return "\(count) items"
            }
            return "Playlist"
        case .musicArtist:
            if let count = item.albumCount {
                return "\(count) albums"
            }
            return "Artist"
        default:
            return item.productionYear.map { String($0) } ?? ""
        }
    }

    // MARK: - Private

    private func loadLibraryName(client: MediaServerClient) async {
        guard !parentId.isEmpty else { return }
        do {
            let item = try await client.userLibraryApi.getItem(itemId: parentId)
            libraryName = item.name
        } catch {}
    }

    private func loadAllRows(client: MediaServerClient) async {
        await withTaskGroup(of: (String, [ServerItem]).self) { group in
            group.addTask { await ("latestAudio", self.loadLatestAudio(client: client)) }
            group.addTask { await ("lastPlayed", self.loadLastPlayed(client: client)) }
            group.addTask { await ("favoriteAlbums", self.loadFavoriteAlbums(client: client)) }
            group.addTask { await ("playlists", self.loadPlaylists(client: client)) }

            for await (rowId, items) in group {
                if let index = rows.firstIndex(where: { $0.id == rowId }) {
                    rows[index].items = items
                    rows[index].isLoading = false
                }
            }
        }
    }

    private func loadLatestAudio(client: MediaServerClient) async -> [ServerItem] {
        do {
            let request = GetLatestMediaRequest(
                parentId: parentId,
                includeItemTypes: [.audio],
                limit: 50,
                groupItems: true,
                imageTypeLimit: 1
            )
            return try await client.itemsApi.getLatestMedia(request: request)
        } catch { return [] }
    }

    private func loadLastPlayed(client: MediaServerClient) async -> [ServerItem] {
        do {
            let request = GetItemsRequest(
                parentId: parentId,
                recursive: true,
                includeItemTypes: [.audio],
                sortBy: [.datePlayed],
                sortOrder: .descending,
                filters: [.isPlayed],
                limit: 50,
                imageTypeLimit: 1
            )
            let result = try await client.itemsApi.getItems(request: request)
            return result.items
        } catch { return [] }
    }

    private func loadFavoriteAlbums(client: MediaServerClient) async -> [ServerItem] {
        do {
            let request = GetItemsRequest(
                parentId: parentId,
                recursive: true,
                includeItemTypes: [.musicAlbum],
                sortBy: [.sortName],
                filters: [.isFavorite],
                imageTypeLimit: 1
            )
            let result = try await client.itemsApi.getItems(request: request)
            return result.items
        } catch { return [] }
    }

    private func loadPlaylists(client: MediaServerClient) async -> [ServerItem] {
        do {
            let request = GetItemsRequest(
                recursive: true,
                includeItemTypes: [.playlist],
                sortBy: [.dateCreated],
                sortOrder: .descending,
                imageTypeLimit: 1
            )
            let result = try await client.itemsApi.getItems(request: request)
            return result.items
        } catch { return [] }
    }

    private func backdropUrl(for item: ServerItem) -> String? {
        guard let imageApi else { return nil }

        if let tags = item.backdropImageTags, let tag = tags.first {
            return imageApi.getItemImageUrl(
                itemId: item.id, imageType: .backdrop,
                maxWidth: 1920, maxHeight: nil, tag: tag
            )
        }

        if let parentTags = item.parentBackdropImageTags,
           let parentId = item.parentBackdropItemId, !parentTags.isEmpty {
            return imageApi.getItemImageUrl(
                itemId: parentId, imageType: .backdrop,
                maxWidth: 1920, maxHeight: nil, tag: parentTags.first
            )
        }

        if item.type == .audio, let albumId = item.albumId {
            return imageApi.getItemImageUrl(
                itemId: albumId, imageType: .primary,
                maxWidth: 600, maxHeight: nil, tag: item.albumPrimaryImageTag
            )
        }

        return nil
    }
}
