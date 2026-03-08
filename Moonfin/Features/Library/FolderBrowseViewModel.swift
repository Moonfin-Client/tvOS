import Foundation
import Combine

struct FolderBreadcrumb: Identifiable, Hashable {
    let id: String
    let name: String
}

struct FolderRow: Identifiable {
    let id: String
    let title: String
    let items: [ServerItem]
}

@MainActor
final class FolderBrowseViewModel: ObservableObject {
    @Published private(set) var rootRows: [FolderRow] = []
    @Published private(set) var items: [ServerItem] = []
    @Published private(set) var breadcrumbs: [FolderBreadcrumb] = []
    @Published private(set) var isLoading = false
    @Published private(set) var focusedItem: ServerItem?

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private let initialFolderId: String?
    private var cancellables = Set<AnyCancellable>()

    var isRootView: Bool { breadcrumbs.isEmpty }

    init(container: AppContainer, folderId: String? = nil) {
        self.container = container
        self.initialFolderId = folderId

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
        if let folderId = initialFolderId {
            Task { await navigateToFolder(id: folderId, name: "Folder") }
        } else {
            Task { await loadRootFolders() }
        }
    }

    func navigateToFolder(id: String, name: String) async {
        breadcrumbs.append(FolderBreadcrumb(id: id, name: name))
        await loadFolderContents(parentId: id)
    }

    func navigateToBreadcrumb(_ crumb: FolderBreadcrumb) async {
        guard let idx = breadcrumbs.firstIndex(where: { $0.id == crumb.id }) else { return }
        breadcrumbs = Array(breadcrumbs.prefix(through: idx))
        await loadFolderContents(parentId: crumb.id)
    }

    func navigateToRoot() async {
        breadcrumbs = []
        items = []
        await loadRootFolders()
    }

    func setFocusedItem(_ item: ServerItem) {
        focusedItem = item
        if let url = backdropUrl(for: item) {
            backgroundService.setBackground(url: url)
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
        if item.isFolder == true {
            return item.childCount.map { "\($0) items" } ?? "Folder"
        }
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
        default:
            return item.productionYear.map { String($0) } ?? ""
        }
    }

    private func loadRootFolders() async {
        guard let client else { return }
        isLoading = true

        do {
            let request = GetItemsRequest(
                recursive: false,
                includeItemTypes: [.folder, .collectionFolder],
                sortBy: [.sortName],
                sortOrder: .ascending,
                imageTypeLimit: 1,
                enableTotalRecordCount: false
            )
            let result = try await client.itemsApi.getItems(request: request)
            let folders = result.items

            var rows: [FolderRow] = []
            await withTaskGroup(of: FolderRow?.self) { group in
                for folder in folders {
                    group.addTask {
                        let childRequest = GetItemsRequest(
                            parentId: folder.id,
                            sortBy: [.sortName],
                            sortOrder: .ascending,
                            limit: 50,
                            imageTypeLimit: 1,
                            enableTotalRecordCount: false
                        )
                        let childResult = try? await client.itemsApi.getItems(request: childRequest)
                        guard let children = childResult?.items, !children.isEmpty else { return nil }
                        return FolderRow(id: folder.id, title: folder.name, items: children)
                    }
                }
                for await row in group {
                    if let row { rows.append(row) }
                }
            }

            let folderOrder = folders.map(\.id)
            rootRows = rows.sorted { a, b in
                (folderOrder.firstIndex(of: a.id) ?? 0) < (folderOrder.firstIndex(of: b.id) ?? 0)
            }
        } catch {
            rootRows = []
        }

        isLoading = false
    }

    private func loadFolderContents(parentId: String) async {
        guard let client else { return }
        isLoading = true

        do {
            let request = GetItemsRequest(
                parentId: parentId,
                sortBy: [.sortName],
                sortOrder: .ascending,
                imageTypeLimit: 1,
                enableTotalRecordCount: false
            )
            let result = try await client.itemsApi.getItems(request: request)
            items = result.items
        } catch {
            items = []
        }

        isLoading = false
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
        let tag = item.imageTags?["Primary"]
        return imageApi.getItemImageUrl(
            itemId: item.id, imageType: .primary,
            maxWidth: 1920, maxHeight: nil, tag: tag
        )
    }
}
