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
    private var dataSources: [String: RowDataSource] = [:]
    private var userViews: [ServerItem] = []

    private static let selectionDebounceMs: UInt64 = 150_000_000
    private static let backdropDebounceMs: UInt64 = 200_000_000
    private static let chunkSize = 15
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
            dataSources = [:]
            for section in sections {
                builtRows.append(contentsOf: buildRowDefinitions(for: section))
            }
            rows = builtRows
            isInitialLoad = false

            await loadAllRows(client: client)
        }
    }

    func refreshContent() {
        Task {
            guard let client else { return }
            let service = container.dataRefreshService

            for (rowId, source) in dataSources {
                if source.needsRefresh(service: service) {
                    await source.retrieve(client: client)
                    syncRow(rowId)
                }
            }
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
            return [makeRow(
                id: "resume_video",
                title: "Continue Watching",
                rowType: .continueWatching,
                queryType: .resume(GetResumeItemsRequest(
                    mediaTypes: [.video],
                    fields: Self.defaultFields,
                    enableImages: true,
                    imageTypeLimit: 1
                )),
                triggers: [.moviePlayback, .tvPlayback]
            )]

        case .nextUp:
            return [makeRow(
                id: "next_up",
                title: "Next Up",
                rowType: .nextUp,
                queryType: .nextUp(GetNextUpRequest(
                    fields: Self.defaultFields,
                    enableImages: true,
                    imageTypeLimit: 1
                )),
                triggers: [.tvPlayback]
            )]

        case .latestMedia:
            return latestMediaViewTypes.map { view in
                makeRow(
                    id: "latest_\(view.id)",
                    title: "Latest \(view.name)",
                    rowType: .latestMedia(libraryId: view.id),
                    queryType: .latestMedia(GetLatestMediaRequest(
                        parentId: view.id,
                        fields: Self.defaultFields,
                        limit: Self.latestMediaLimit,
                        groupItems: true,
                        imageTypeLimit: 1
                    )),
                    triggers: [.libraryUpdated]
                )
            }

        case .libraryTiles:
            return [makeRow(
                id: "library_tiles",
                title: "Libraries",
                rowType: .libraryTiles,
                queryType: .staticItems(userViews),
                triggers: []
            )]

        case .resumeAudio:
            return [makeRow(
                id: "resume_audio",
                title: "Continue Listening",
                rowType: .resumeAudio,
                queryType: .resume(GetResumeItemsRequest(
                    mediaTypes: [.audio],
                    fields: Self.defaultFields,
                    enableImages: true,
                    imageTypeLimit: 1
                )),
                triggers: [.musicPlayback]
            )]

        case .playlists:
            return [makeRow(
                id: "playlists",
                title: "Playlists",
                rowType: .playlists,
                queryType: .items(GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.playlist],
                    sortBy: [.dateCreated],
                    sortOrder: .descending,
                    fields: Self.defaultFields,
                    enableImages: true,
                    imageTypeLimit: 1
                )),
                triggers: [.libraryUpdated]
            )]

        case .liveTv:
            return [makeRow(
                id: "live_tv",
                title: "Live TV",
                rowType: .liveTv,
                queryType: .liveTvPrograms,
                triggers: []
            )]

        case .none:
            return []
        }
    }

    private func makeRow(
        id: String,
        title: String,
        rowType: HomeRowType,
        queryType: RowQueryType,
        triggers: Set<ChangeTriggerType>
    ) -> HomeRow {
        let source = RowDataSource(
            queryType: queryType,
            changeTriggers: triggers,
            chunkSize: Self.chunkSize
        )
        dataSources[id] = source
        return HomeRow(id: id, title: title, rowType: rowType)
    }

    private var latestMediaViewTypes: [ServerItem] {
        let supportedTypes: Set<String> = ["movies", "tvshows", "music", "mixed"]
        return userViews.filter { view in
            guard let ct = view.collectionType?.lowercased() else { return true }
            return supportedTypes.contains(ct)
        }
    }

    private func loadAllRows(client: MediaServerClient) async {
        await withTaskGroup(of: String?.self) { group in
            for (rowId, source) in dataSources {
                group.addTask {
                    await source.retrieve(client: client)
                    return rowId
                }
            }
            for await rowId in group {
                guard let rowId, !Task.isCancelled else { continue }
                syncRow(rowId)
            }
        }
    }

    private func syncRow(_ rowId: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowId }),
              let source = dataSources[rowId]
        else { return }
        rows[index].items = source.items
        rows[index].isLoading = source.isLoading
        rows[index].totalItemCount = source.totalItemCount
    }

    func loadMoreIfNeeded(row: HomeRow, currentIndex: Int) {
        guard let source = dataSources[row.id],
              source.shouldLoadMore(currentIndex: currentIndex),
              let client
        else { return }

        Task {
            await source.loadMore(client: client)
            syncRow(row.id)
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
