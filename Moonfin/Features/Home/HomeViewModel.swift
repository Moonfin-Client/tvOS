import SwiftUI
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var selectedItemState: SelectedItemState = .empty
    @Published private(set) var rows: [HomeRow] = []
    @Published private(set) var isInitialLoad = true
    @Published private(set) var isMediaBarActive: Bool = false
    @Published private(set) var isMediaBarLoading: Bool = true

    var hasFocusableContent: Bool {
        if isMediaBarActive { return true }
        if mediaBarViewModel.isEnabled && isMediaBarLoading { return false }
        return rows.contains(where: { !$0.items.isEmpty })
    }

    let backgroundService = BackgroundService()
    let mediaBarViewModel: MediaBarViewModel
    let mediaBarRatingsViewModel: MediaBarRatingsViewModel

    private let container: AppContainer
    private var selectionDebounceTask: Task<Void, Never>?
    private var backdropDebounceTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var dataSources: [String: RowDataSource] = [:]
    private var userViews: [ServerItem] = []
    private var cancellables = Set<AnyCancellable>()
    private static let selectionDebounceMs: UInt64 = 150_000_000
    private static let backdropDebounceMs: UInt64 = 200_000_000
    private static let chunkSize = 15
    private static let latestMediaLimit = 50
    private static let multiServerLimit = 30

    private static let defaultFields: [ItemField] = [
        .overview, .primaryImageAspectRatio, .genres, .mediaSources, .providerIds
    ]

    init(container: AppContainer) {
        self.container = container
        self.mediaBarViewModel = MediaBarViewModel(container: container)
        self.mediaBarRatingsViewModel = MediaBarRatingsViewModel(
            mdbListRepository: container.mdbListRepository,
            userPreferences: container.userPreferences
        )
        backgroundService.configure(preferences: container.userPreferences)
        observeMediaBar()

        backgroundService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        mediaBarRatingsViewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func observeMediaBar() {
        mediaBarViewModel.$state
            .map { state in
                if case .ready(let items) = state, !items.isEmpty { return true }
                return false
            }
            .assign(to: &$isMediaBarActive)

        mediaBarViewModel.$state
            .map { state in
                if case .loading = state { return true }
                return false
            }
            .assign(to: &$isMediaBarLoading)
    }

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    var imageApi: ServerImageApi? { client?.imageApi }

    var watchedIndicator: WatchedIndicatorBehavior {
        container.userPreferences[UserPreferences.watchedIndicator]
    }

    var multiServerActive: Bool {
        container.userPreferences[UserPreferences.enableMultiServerLibraries]
            && container.serverRepository.storedServers.value.count > 1
    }

    func serverName(for item: ServerItem) -> String? {
        guard multiServerActive,
              let sid = item.effectiveServerId,
              let uuid = UUID(uuidString: sid),
              let server = container.serverRepository.storedServers.value.first(where: { $0.id == uuid })
        else { return nil }
        return server.name
    }

    private func imageApi(for item: ServerItem) -> ServerImageApi? {
        if let serverId = item.effectiveServerId,
           let serverUUID = UUID(uuidString: serverId),
           let server = container.serverRepository.storedServers.value.first(where: { $0.id == serverUUID }) {
            return container.serverClientFactory.client(for: server).imageApi
        }
        return imageApi
    }

    func loadContent(forceReload: Bool = false) {
        guard forceReload || isInitialLoad else {
            refreshContent()
            return
        }
        loadTask?.cancel()
        loadTask = Task {
            guard let client else {
                await mediaBarViewModel.load()
                return
            }

            let sections = activeHomeSections()

            if multiServerActive {
                await loadMultiServerContent(sections: sections, client: client)
                return
            }

            let viewDependent: Set<HomeSectionType> = [.latestMedia, .libraryTiles]
            let needsViews = mediaBarViewModel.isEnabled
                || sections.contains(where: { viewDependent.contains($0) })

            dataSources = [:]
            var earlyRows: [HomeRow] = []
            for section in sections where !viewDependent.contains(section) {
                earlyRows.append(contentsOf: buildRowDefinitions(for: section))
            }
            rows = earlyRows
            isInitialLoad = false

            let earlyRowIds = Set(dataSources.keys)

            async let earlyLoadTask: Void = loadRows(earlyRowIds, client: client)

            if needsViews {
                userViews = await container.userViewsService.awaitLoaded()
            }

            guard !Task.isCancelled else { return }

            await mediaBarViewModel.load(userViews: userViews)

            await earlyLoadTask

            let lateRows = sections
                .filter { viewDependent.contains($0) }
                .flatMap { buildRowDefinitions(for: $0) }
            if !lateRows.isEmpty {
                rows.append(contentsOf: lateRows)
                let lateRowIds = Set(dataSources.keys).subtracting(earlyRowIds)
                await loadRows(lateRowIds, client: client)
            }

            indexForSpotlight()
        }
    }

    func refreshContent() {
        Task {
            guard let client else { return }
            let service = container.dataRefreshService
            let stale = dataSources.filter { $0.value.needsRefresh(service: service) }
            guard !stale.isEmpty else { return }

            await withTaskGroup(of: String.self) { group in
                for (rowId, source) in stale {
                    group.addTask {
                        await source.retrieve(client: client)
                        return rowId
                    }
                }
                for await rowId in group {
                    syncRow(rowId)
                }
            }
        }
    }

    private func indexForSpotlight() {
        let allItems = rows.flatMap(\.items)
        container.spotlightIndexer.indexItems(allItems)
    }

    private func loadMultiServerContent(sections: [HomeSectionType], client: MediaServerClient) async {
        let multiRepo = container.multiServerRepository
        let multiServerSections: Set<HomeSectionType> = [.resume, .nextUp, .latestMedia, .libraryTiles]

        dataSources = [:]

        let needsViews = mediaBarViewModel.isEnabled
            || sections.contains(.latestMedia) || sections.contains(.libraryTiles)

        var aggregatedLibraries: [AggregatedLibrary] = []
        if needsViews {
            aggregatedLibraries = await multiRepo.getAggregatedLibraries()
            userViews = aggregatedLibraries.map(\.library)
        }

        guard !Task.isCancelled else { return }

        await mediaBarViewModel.load(userViews: userViews)

        var resultRows: [HomeRow] = []

        for section in sections {
            if multiServerSections.contains(section) {
                switch section {
                case .resume:
                    let mergeEnabled = container.userPreferences[UserPreferences.mergeContinueWatchingNextUp]
                    let items: [ServerItem]
                    if mergeEnabled {
                        items = await multiRepo.getAggregatedMergedContinueWatching(limit: Self.multiServerLimit)
                    } else {
                        items = await multiRepo.getAggregatedResumeItems(mediaTypes: [.video], limit: Self.multiServerLimit)
                    }
                    resultRows.append(makeStaticRow(
                        id: "ms_resume_video", title: "Continue Watching",
                        rowType: .continueWatching, items: items
                    ))
                    if mergeEnabled { continue }

                case .nextUp:
                    if container.userPreferences[UserPreferences.mergeContinueWatchingNextUp] {
                        continue
                    }
                    let items = await multiRepo.getAggregatedNextUpItems(limit: Self.multiServerLimit)
                    resultRows.append(makeStaticRow(
                        id: "ms_next_up", title: "Next Up",
                        rowType: .nextUp, items: items
                    ))

                case .latestMedia:
                    let supportedTypes: Set<String> = ["movies", "tvshows", "music", "mixed"]
                    let filteredLibs = aggregatedLibraries.filter { lib in
                        guard let ct = lib.library.collectionType?.lowercased() else { return true }
                        return supportedTypes.contains(ct)
                    }
                    for lib in filteredLibs {
                        let items = await multiRepo.getAggregatedLatestItems(
                            parentId: lib.library.id,
                            limit: Self.latestMediaLimit,
                            serverId: lib.server.id
                        )
                        resultRows.append(makeStaticRow(
                            id: "ms_latest_\(lib.server.id.uuidString)_\(lib.library.id)",
                            title: "Latest \(lib.displayName)",
                            rowType: .latestMedia(libraryId: lib.library.id),
                            items: items
                        ))
                    }

                case .libraryTiles:
                    let items = aggregatedLibraries.map(\.library)
                    resultRows.append(makeStaticRow(
                        id: "ms_library_tiles", title: "Libraries",
                        rowType: .libraryTiles, items: items
                    ))

                default:
                    break
                }
            } else {
                resultRows.append(contentsOf: buildRowDefinitions(for: section))
            }

            guard !Task.isCancelled else { return }
        }

        rows = resultRows
        isInitialLoad = false

        let singleRowIds = Set(dataSources.keys).filter { id in
            !id.hasPrefix("ms_")
        }
        if !singleRowIds.isEmpty {
            await loadRows(singleRowIds, client: client)
        }

        indexForSpotlight()
    }

    private func makeStaticRow(
        id: String, title: String, rowType: HomeRowType, items: [ServerItem]
    ) -> HomeRow {
        let filtered = container.parentalControlsRepository.filterItems(items)
        let source = RowDataSource(queryType: .staticItems(filtered), changeTriggers: [], chunkSize: Self.chunkSize)
        source.preload(filtered)
        dataSources[id] = source
        return HomeRow(id: id, title: title, items: filtered, rowType: rowType, isLoading: false, totalItemCount: filtered.count)
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
            let mergeEnabled = container.userPreferences[UserPreferences.mergeContinueWatchingNextUp]
            if mergeEnabled {
                return [makeRow(
                    id: "merged_continue_watching",
                    title: "Continue Watching",
                    rowType: .continueWatching,
                    queryType: .mergedContinueWatching(
                        resume: GetResumeItemsRequest(
                            mediaTypes: [.video],
                            fields: Self.defaultFields,
                            enableImages: true,
                            imageTypeLimit: 1
                        ),
                        nextUp: GetNextUpRequest(
                            fields: Self.defaultFields,
                            enableImages: true,
                            imageTypeLimit: 1
                        )
                    ),
                    triggers: [.moviePlayback, .tvPlayback]
                )]
            }
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
            if container.userPreferences[UserPreferences.mergeContinueWatchingNextUp] {
                return []
            }
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
            let buttonItems: [ServerItem] = [
                .placeholder(id: "ltv_guide", name: "Guide"),
                .placeholder(id: "ltv_recordings", name: "Recordings"),
                .placeholder(id: "ltv_schedule", name: "Schedule"),
                .placeholder(id: "ltv_series", name: "Series"),
            ]
            return [
                makeRow(
                    id: "live_tv_buttons",
                    title: "Live TV",
                    rowType: .liveTvButtons,
                    queryType: .staticItems(buttonItems),
                    triggers: []
                ),
                makeRow(
                    id: "live_tv_on_now",
                    title: "On Now",
                    rowType: .liveTvOnNow,
                    queryType: .liveTvOnNow,
                    triggers: []
                ),
                makeRow(
                    id: "live_tv_coming_up",
                    title: "Coming Up",
                    rowType: .liveTvComingUp,
                    queryType: .liveTvComingUp,
                    triggers: []
                ),
            ]

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

    private func loadRows(_ rowIds: Set<String>, client: MediaServerClient) async {
        await withTaskGroup(of: String?.self) { group in
            for rowId in rowIds {
                guard let source = dataSources[rowId] else { continue }
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
        let filtered = container.parentalControlsRepository.filterItems(source.items)
        rows[index].items = filtered
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
            mediaBarRatingsViewModel.loadRatings(for: item)
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
        guard let api = imageApi(for: item) else { return nil }
        let tag = item.imageTags?["Primary"]
        return api.getItemImageUrl(
            itemId: item.id,
            imageType: .primary,
            maxWidth: 300,
            maxHeight: nil,
            tag: tag
        )
    }

    func thumbImageUrl(for item: ServerItem) -> String? {
        guard let api = imageApi(for: item) else { return nil }
        if let tag = item.imageTags?["Thumb"] {
            return api.getItemImageUrl(
                itemId: item.id,
                imageType: .thumb,
                maxWidth: 480,
                maxHeight: nil,
                tag: tag
            )
        }
        if let tags = item.backdropImageTags, let tag = tags.first {
            return api.getItemImageUrl(
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
        guard let api = imageApi(for: item) else { return [] }
        var urls: [String] = []

        if let tags = item.backdropImageTags, !tags.isEmpty {
            for tag in tags {
                urls.append(api.getItemImageUrl(
                    itemId: item.id, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: tag
                ))
            }
        }

        if urls.isEmpty, let parentTags = item.parentBackdropImageTags,
           let parentId = item.parentBackdropItemId, !parentTags.isEmpty {
            for tag in parentTags {
                urls.append(api.getItemImageUrl(
                    itemId: parentId, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: tag
                ))
            }
        }

        if urls.isEmpty, let seriesId = item.seriesId {
            urls.append(api.getItemImageUrl(
                itemId: seriesId, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: nil
            ))
        }

        return urls
    }

    private func logoImageUrl(for item: ServerItem) -> String? {
        guard let api = imageApi(for: item) else { return nil }
        if let logoTag = item.imageTags?["Logo"] {
            return api.getItemImageUrl(
                itemId: item.id, imageType: .logo, maxWidth: 400, maxHeight: nil, tag: logoTag
            )
        }
        if let seriesId = item.seriesId {
            return api.getItemImageUrl(
                itemId: seriesId, imageType: .logo, maxWidth: 400, maxHeight: nil, tag: nil
            )
        }
        return nil
    }
}
