import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var selectedItemState: SelectedItemState = .empty
    @Published private(set) var rows: [HomeRow] = []
    @Published private(set) var isInitialLoad = true

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private var selectionDebounceTask: Task<Void, Never>?
    private var backdropDebounceTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var paginationTasks: [String: Task<Void, Never>] = [:]
    private var userViews: [ServerItem] = []

    private static let selectionDebounceMs: UInt64 = 150_000_000
    private static let backdropDebounceMs: UInt64 = 200_000_000
    private static let chunkSize = 15
    private static let maxItems = 100
    private static let latestMediaLimit = 50

    private static let defaultFields: [ItemField] = [
        .overview, .primaryImageAspectRatio, .genres, .mediaSources
    ]

    init(container: AppContainer) {
        self.container = container
    }

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    var imageApi: ServerImageApi? { client?.imageApi }

    var watchedIndicator: WatchedIndicatorBehavior {
        container.userPreferences[UserPreferences.watchedIndicator]
    }

    func loadContent() {
        loadTask?.cancel()
        loadTask = Task {
            guard let client else { return }

            let sections = activeHomeSections()

            if sections.contains(where: { $0 == .latestMedia || $0 == .libraryTiles }) {
                do {
                    userViews = try await client.userViewsApi.getUserViews(userId: client.userId ?? "")
                } catch {
                    userViews = []
                }
            }

            guard !Task.isCancelled else { return }

            var builtRows: [HomeRow] = []
            for section in sections {
                builtRows.append(contentsOf: buildRowDefinitions(for: section))
            }
            rows = builtRows
            isInitialLoad = false

            await loadAllRows()
        }
    }

    private func activeHomeSections() -> [HomeSectionType] {
        let raw = container.userPreferences[UserPreferences.homeSections]
        guard !raw.isEmpty else {
            return HomeSectionType.defaults.filter(\.enabled).map(\.type)
        }
        return raw.split(separator: ",")
            .compactMap { HomeSectionType(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
    }

    private func buildRowDefinitions(for section: HomeSectionType) -> [HomeRow] {
        switch section {
        case .resume:
            return [HomeRow(id: "resume_video", title: "Continue Watching", rowType: .continueWatching)]
        case .nextUp:
            return [HomeRow(id: "next_up", title: "Next Up", rowType: .nextUp)]
        case .latestMedia:
            return latestMediaViewTypes.map { view in
                HomeRow(
                    id: "latest_\(view.id)",
                    title: "Latest \(view.name)",
                    rowType: .latestMedia(libraryId: view.id)
                )
            }
        case .libraryTiles:
            return [HomeRow(id: "library_tiles", title: "Libraries", rowType: .libraryTiles)]
        case .resumeAudio:
            return [HomeRow(id: "resume_audio", title: "Continue Listening", rowType: .resumeAudio)]
        case .playlists:
            return [HomeRow(id: "playlists", title: "Playlists", rowType: .playlists)]
        case .liveTv:
            return [HomeRow(id: "live_tv", title: "Live TV", rowType: .liveTv)]
        case .none:
            return []
        }
    }

    private var latestMediaViewTypes: [ServerItem] {
        let supportedTypes: Set<String> = ["movies", "tvshows", "music", "mixed"]
        return userViews.filter { view in
            guard let ct = view.collectionType?.lowercased() else { return true }
            return supportedTypes.contains(ct)
        }
    }

    private func loadAllRows() async {
        await withTaskGroup(of: (String, [ServerItem], Int)?.self) { group in
            for row in rows {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.fetchRowData(row)
                }
            }
            for await result in group {
                guard let (rowId, items, total) = result else { continue }
                guard !Task.isCancelled else { return }
                if let index = rows.firstIndex(where: { $0.id == rowId }) {
                    rows[index].items = items
                    rows[index].totalItemCount = total
                    rows[index].isLoading = false
                }
            }
        }
    }

    private func fetchRowData(_ row: HomeRow) async -> (String, [ServerItem], Int)? {
        guard let client else { return nil }
        do {
            switch row.rowType {
            case .continueWatching:
                let result = try await client.itemsApi.getResumeItems(request: GetResumeItemsRequest(
                    mediaTypes: [.video],
                    fields: Self.defaultFields,
                    limit: Self.chunkSize,
                    enableImages: true,
                    imageTypeLimit: 1
                ))
                return (row.id, result.items, result.totalRecordCount)

            case .nextUp:
                let result = try await client.itemsApi.getNextUp(request: GetNextUpRequest(
                    fields: Self.defaultFields,
                    limit: Self.chunkSize,
                    enableImages: true,
                    imageTypeLimit: 1
                ))
                return (row.id, result.items, result.totalRecordCount)

            case .latestMedia(let libraryId):
                let items = try await client.itemsApi.getLatestMedia(request: GetLatestMediaRequest(
                    parentId: libraryId,
                    fields: Self.defaultFields,
                    limit: Self.latestMediaLimit,
                    groupItems: true,
                    imageTypeLimit: 1
                ))
                return (row.id, Array(items.prefix(Self.chunkSize)), items.count)

            case .libraryTiles:
                return (row.id, userViews, userViews.count)

            case .resumeAudio:
                let result = try await client.itemsApi.getResumeItems(request: GetResumeItemsRequest(
                    mediaTypes: [.audio],
                    fields: Self.defaultFields,
                    limit: Self.chunkSize,
                    enableImages: true,
                    imageTypeLimit: 1
                ))
                return (row.id, result.items, result.totalRecordCount)

            case .playlists:
                let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.playlist],
                    sortBy: [.dateCreated],
                    sortOrder: .descending,
                    fields: Self.defaultFields,
                    limit: Self.latestMediaLimit,
                    enableImages: true,
                    imageTypeLimit: 1
                ))
                return (row.id, result.items, result.totalRecordCount)

            case .liveTv:
                let result = try await client.liveTvApi.getRecommendedPrograms(
                    userId: client.userId,
                    limit: Self.chunkSize
                )
                return (row.id, result.items, result.totalRecordCount)
            }
        } catch {
            return (row.id, [], 0)
        }
    }

    func loadMoreIfNeeded(row: HomeRow, currentIndex: Int) {
        let threshold = row.items.count - Int(Double(Self.chunkSize) / 1.7)
        guard currentIndex >= threshold,
              row.items.count < row.totalItemCount,
              row.items.count < Self.maxItems,
              paginationTasks[row.id] == nil
        else { return }

        paginationTasks[row.id] = Task {
            defer { paginationTasks[row.id] = nil }
            guard let client else { return }

            do {
                let startIndex = row.items.count
                var newItems: [ServerItem] = []

                switch row.rowType {
                case .continueWatching:
                    let result = try await client.itemsApi.getResumeItems(request: GetResumeItemsRequest(
                        mediaTypes: [.video],
                        fields: Self.defaultFields,
                        limit: Self.chunkSize,
                        startIndex: startIndex,
                        enableImages: true,
                        imageTypeLimit: 1
                    ))
                    newItems = result.items

                case .nextUp:
                    let result = try await client.itemsApi.getNextUp(request: GetNextUpRequest(
                        fields: Self.defaultFields,
                        limit: Self.chunkSize,
                        startIndex: startIndex,
                        enableImages: true,
                        imageTypeLimit: 1
                    ))
                    newItems = result.items

                case .latestMedia:
                    return

                case .resumeAudio:
                    let result = try await client.itemsApi.getResumeItems(request: GetResumeItemsRequest(
                        mediaTypes: [.audio],
                        fields: Self.defaultFields,
                        limit: Self.chunkSize,
                        startIndex: startIndex,
                        enableImages: true,
                        imageTypeLimit: 1
                    ))
                    newItems = result.items

                case .playlists:
                    let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                        recursive: true,
                        includeItemTypes: [.playlist],
                        sortBy: [.dateCreated],
                        sortOrder: .descending,
                        fields: Self.defaultFields,
                        limit: Self.chunkSize,
                        startIndex: startIndex,
                        enableImages: true,
                        imageTypeLimit: 1
                    ))
                    newItems = result.items

                case .liveTv, .libraryTiles:
                    return
                }

                guard !Task.isCancelled, !newItems.isEmpty else { return }
                if let index = rows.firstIndex(where: { $0.id == row.id }) {
                    rows[index].items.append(contentsOf: newItems)
                }
            } catch { }
        }
    }

    func onItemFocused(_ item: ServerItem?) {
        guard let item else {
            selectionDebounceTask?.cancel()
            backdropDebounceTask?.cancel()
            selectedItemState = .empty
            backgroundService.clearBackground()
            return
        }

        selectionDebounceTask?.cancel()
        selectionDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.selectionDebounceMs)
            guard !Task.isCancelled else { return }
            selectedItemState = buildSelectedState(for: item)
        }

        backdropDebounceTask?.cancel()
        backdropDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.backdropDebounceMs)
            guard !Task.isCancelled else { return }
            let urls = backdropUrls(for: item)
            backgroundService.setBackground(urls: urls)
        }
    }

    func posterImageUrl(for item: ServerItem) -> String? {
        guard let imageApi else { return nil }
        let tag = item.imageTags?["Primary"]
        return imageApi.getItemImageUrl(
            itemId: item.id,
            imageType: .primary,
            maxWidth: 300,
            maxHeight: nil,
            tag: tag
        )
    }

    func thumbImageUrl(for item: ServerItem) -> String? {
        guard let imageApi else { return nil }
        if let tag = item.imageTags?["Thumb"] {
            return imageApi.getItemImageUrl(
                itemId: item.id,
                imageType: .thumb,
                maxWidth: 480,
                maxHeight: nil,
                tag: tag
            )
        }
        if let tags = item.backdropImageTags, let tag = tags.first {
            return imageApi.getItemImageUrl(
                itemId: item.id,
                imageType: .backdrop,
                maxWidth: 480,
                maxHeight: nil,
                tag: tag
            )
        }
        return posterImageUrl(for: item)
    }

    private func buildSelectedState(for item: ServerItem) -> SelectedItemState {
        SelectedItemState(
            title: item.name,
            summary: item.overview ?? "",
            item: item,
            logoUrl: logoImageUrl(for: item),
            backdropUrl: backdropUrls(for: item).first
        )
    }

    private func backdropUrls(for item: ServerItem) -> [String] {
        guard let imageApi else { return [] }
        var urls: [String] = []

        if let tags = item.backdropImageTags, !tags.isEmpty {
            for tag in tags {
                urls.append(imageApi.getItemImageUrl(
                    itemId: item.id, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: tag
                ))
            }
        }

        if urls.isEmpty, let parentTags = item.parentBackdropImageTags,
           let parentId = item.parentBackdropItemId, !parentTags.isEmpty {
            for tag in parentTags {
                urls.append(imageApi.getItemImageUrl(
                    itemId: parentId, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: tag
                ))
            }
        }

        if urls.isEmpty, let seriesId = item.seriesId {
            urls.append(imageApi.getItemImageUrl(
                itemId: seriesId, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: nil
            ))
        }

        return urls
    }

    private func logoImageUrl(for item: ServerItem) -> String? {
        guard let imageApi else { return nil }
        if let logoTag = item.imageTags?["Logo"] {
            return imageApi.getItemImageUrl(
                itemId: item.id, imageType: .logo, maxWidth: 400, maxHeight: nil, tag: logoTag
            )
        }
        if let seriesId = item.seriesId {
            return imageApi.getItemImageUrl(
                itemId: seriesId, imageType: .logo, maxWidth: 400, maxHeight: nil, tag: nil
            )
        }
        return nil
    }
}
