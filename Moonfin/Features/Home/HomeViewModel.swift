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
    private var rowClients: [String: MediaServerClient] = [:]
    private var userViews: [ServerItem] = []
    private var cancellables = Set<AnyCancellable>()
    private let topShelfCacheWriter = TopShelfCacheWriter()
    private static let selectionDebounceMs: UInt64 = 150_000_000
    private static let backdropDebounceMs: UInt64 = 200_000_000
    private static let chunkSize = 15
    private static let multiServerLimit = 30

    private static let defaultFields: [ItemField] = [
        .overview, .genres, .providerIds, .mediaSources, .mediaStreams
    ]

    init(container: AppContainer) {
        self.container = container
        self.mediaBarViewModel = MediaBarViewModel(container: container)
        self.mediaBarRatingsViewModel = MediaBarRatingsViewModel(
            mdbListRepository: container.mdbListRepository,
            tmdbRepository: container.tmdbRepository,
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

        container.pluginSyncService.$syncCompletedCount
            .dropFirst()
            .filter { $0 > 0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadContent(forceReload: true)
            }
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

    private var queuedForceReload = false

    func loadContent(forceReload: Bool = false) {
        if forceReload && loadTask != nil {
            queuedForceReload = true
            return
        }
        guard forceReload || isInitialLoad else {
            refreshContent()
            return
        }
        queuedForceReload = false
        loadTask?.cancel()
        loadTask = Task {
            defer { finishLoad() }
            guard let client else {
                await mediaBarViewModel.load()
                rows = []
                isInitialLoad = false
                return
            }

            let sections = activeHomeSections()

            if multiServerActive {
                await loadMultiServerContent(sections: sections, client: client)
                return
            }

            let viewDependent: Set<HomeSectionType> = [.latestMedia, .myMedia, .myMediaSmall]
            let needsViews = mediaBarViewModel.isEnabled
                || sections.contains(where: { viewDependent.contains($0) })

            dataSources = [:]
            rowClients = [:]
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

            guard !Task.isCancelled else { return }

            let lateRows = sections
                .filter { viewDependent.contains($0) }
                .flatMap { buildRowDefinitions(for: $0) }
            if !lateRows.isEmpty {
                rows.append(contentsOf: lateRows)
                reorderRowsBySection(sections)
                let lateRowIds = Set(dataSources.keys).subtracting(earlyRowIds)
                await loadRows(lateRowIds, client: client)
            }

            ensureFallbackLibraryRowIfNeeded()

            refreshTopShelfCache()

            indexForSpotlight()
        }
    }

    private func finishLoad() {
        loadTask = nil
        if queuedForceReload {
            queuedForceReload = false
            loadContent(forceReload: true)
        }
    }

    func refreshContent() {
        Task {
            guard let client else { return }

            if mediaBarViewModel.isEnabled && mediaBarViewModel.isStale {
                await mediaBarViewModel.load(userViews: userViews)
            }

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
        let multiServerSections: Set<HomeSectionType> = [.resume, .nextUp, .latestMedia, .myMedia, .myMediaSmall]

        dataSources = [:]
        rowClients = [:]

        let sessions = await multiRepo.getLoggedInServers()
        let clientsByServerId = Dictionary(uniqueKeysWithValues: sessions.map { ($0.server.id, $0.client) })

        let needsViews = mediaBarViewModel.isEnabled
            || sections.contains(.latestMedia) || sections.contains(.myMedia) || sections.contains(.myMediaSmall)
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
                    let supportedTypes: Set<String> = ["movies", "tvshows", "music", "mixed", "photos"]
                    let filteredLibs = aggregatedLibraries.filter { lib in
                        guard let ct = lib.library.collectionType?.lowercased() else { return true }
                        return supportedTypes.contains(ct)
                    }
                    for lib in filteredLibs {
                        let rowId = "ms_latest_\(lib.server.id.uuidString)_\(lib.library.id)"
                        if let rowClient = clientsByServerId[lib.server.id] {
                            rowClients[rowId] = rowClient
                        }
                        resultRows.append(makeRow(
                            id: rowId,
                            title: "Latest \(lib.displayName)",
                            rowType: .latestMedia(libraryId: lib.library.id),
                            isMusicLibraryRow: lib.library.collectionType?.lowercased() == "music",
                            queryType: .latestMedia(latestMediaRequest(
                                parentId: lib.library.id,
                                collectionType: lib.library.collectionType
                            )),
                            triggers: [.libraryUpdated]
                        ))
                    }

                case .myMedia:
                    let items = aggregatedLibraries.map(\.library)
                    resultRows.append(makeStaticRow(
                        id: "ms_my_media", title: "My Media",
                        rowType: .myMedia, items: items
                    ))

                case .myMediaSmall:
                    let items = aggregatedLibraries.map(\.library)
                    resultRows.append(makeStaticRow(
                        id: "ms_my_media_small", title: "My Media",
                        rowType: .myMediaSmall, items: items
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
        dedupeNextUpAgainstContinueWatching()
        isInitialLoad = false

        let rowIds = Set(dataSources.keys)
        if !rowIds.isEmpty {
            await loadRows(rowIds, client: client)
        }

        ensureFallbackLibraryRowIfNeeded()

        refreshTopShelfCache()

        indexForSpotlight()
    }

    private func ensureFallbackLibraryRowIfNeeded() {
        guard !userViews.isEmpty else { return }
        let hasHomeContent = rows.contains { !$0.items.isEmpty }
        guard !hasHomeContent else { return }

        let fallbackId = "fallback_libraries"
        guard !rows.contains(where: { $0.id == fallbackId }) else { return }

        rows.append(
            makeStaticRow(
                id: fallbackId,
                title: "Libraries",
                rowType: .myMedia,
                items: userViews
            )
        )
    }

    private func makeStaticRow(
        id: String, title: String, rowType: HomeRowType, items: [ServerItem], isMusicLibraryRow: Bool = false
    ) -> HomeRow {
        let filtered = filterHomeRowItems(items, for: rowType)
        let source = RowDataSource(queryType: .staticItems(filtered), changeTriggers: [], chunkSize: Self.chunkSize)
        source.preload(filtered)
        dataSources[id] = source
        return HomeRow(id: id, title: title, items: filtered, rowType: rowType, isMusicLibraryRow: isMusicLibraryRow, isLoading: false, totalItemCount: filtered.count)
    }

    private func activeHomeSections() -> [HomeSectionType] {
        let raw = container.userPreferences[UserPreferences.homeSections]
        guard !raw.isEmpty else {
            return HomeSectionType.defaults.filter(\.enabled).map(\.type)
        }
        let parsed = raw.split(separator: ",")
            .compactMap { rawValue -> HomeSectionType? in
                let value = String(rawValue).trimmingCharacters(in: .whitespaces)
                return HomeSectionType(rawValue: value) ?? HomeSectionType.from(serverName: value)
            }
            .filter { $0 != .none }

        var seenSections = Set<HomeSectionType>()
        let uniqueParsed = parsed.filter { seenSections.insert($0).inserted }

        if uniqueParsed.isEmpty {
            return HomeSectionType.defaults.filter(\.enabled).map(\.type)
        }

        return uniqueParsed
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
                    isMusicLibraryRow: view.collectionType?.lowercased() == "music",
                    queryType: .latestMedia(latestMediaRequest(
                        parentId: view.id,
                        collectionType: view.collectionType
                    )),
                    triggers: [.libraryUpdated]
                )
            }

        case .myMedia:
            return [makeStaticRow(id: "my_media", title: "My Media", rowType: .myMedia, items: userViews)]

        case .myMediaSmall:
            return [makeStaticRow(id: "my_media_small", title: "My Media", rowType: .myMediaSmall, items: userViews)]

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
        isMusicLibraryRow: Bool = false,
        queryType: RowQueryType,
        triggers: Set<ChangeTriggerType>
    ) -> HomeRow {
        let source = RowDataSource(
            queryType: queryType,
            changeTriggers: triggers,
            chunkSize: Self.chunkSize
        )
        dataSources[id] = source
        return HomeRow(id: id, title: title, rowType: rowType, isMusicLibraryRow: isMusicLibraryRow)
    }

    private var latestMediaViewTypes: [ServerItem] {
        let supportedTypes: Set<String> = ["movies", "tvshows", "music", "mixed", "photos"]
        return userViews.filter { view in
            guard let ct = view.collectionType?.lowercased() else { return true }
            return supportedTypes.contains(ct)
        }
    }

    private func latestMediaRequest(parentId: String, collectionType: String?) -> GetLatestMediaRequest {
        GetLatestMediaRequest(
            parentId: parentId,
            includeItemTypes: latestIncludeItemTypes(for: collectionType),
            fields: Self.defaultFields,
            limit: RowDataSource.maxItems,
            groupItems: false,
            imageTypeLimit: 1,
        )
    }

    private func latestIncludeItemTypes(for collectionType: String?) -> [ItemType]? {
        switch collectionType?.lowercased() {
        case "tvshows":
            return [.series]
        case "music":
            return [.musicAlbum]
        case "movies":
            return [.movie]
        case "photos":
            return [.photoAlbum]
        case "mixed":
            return [.movie, .series, .musicAlbum, .photoAlbum]
        default:
            return nil
        }
    }

    private func dedupeNextUpAgainstContinueWatching() {
        guard let nextUpIndex = rows.firstIndex(where: { $0.rowType == .nextUp }) else { return }

        let continueWatchingItems = rows
            .filter { $0.rowType == .continueWatching }
            .flatMap(\.items)
        let continueWatchingIds = Set(continueWatchingItems.map(\.id))

        let deduped = rows[nextUpIndex].items.filter { item in
            !continueWatchingIds.contains(item.id) && !isInProgress(item)
        }

        rows[nextUpIndex].items = deduped
        rows[nextUpIndex].totalItemCount = deduped.count
    }

    private func isInProgress(_ item: ServerItem) -> Bool {
        guard let userData = item.userData else { return false }
        if userData.played { return false }
        if userData.playbackPositionTicks > 0 { return true }
        if let percent = userData.playedPercentage, percent > 0 { return true }
        return false
    }

    private func loadRows(_ rowIds: Set<String>, client: MediaServerClient) async {
        let rowLoads: [(rowId: String, source: RowDataSource, sourceClient: MediaServerClient)] = rowIds.compactMap { rowId in
            guard let source = dataSources[rowId] else { return nil }
            let sourceClient = rowClients[rowId] ?? client
            return (rowId, source, sourceClient)
        }

        await withTaskGroup(of: String?.self) { group in
            for load in rowLoads {
                group.addTask {
                    await load.source.retrieve(client: load.sourceClient)
                    return load.rowId
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
        let rowType = rows[index].rowType
        let filtered = filterHomeRowItems(source.items, for: rowType)
        rows[index].items = filtered
        rows[index].isLoading = source.isLoading
        rows[index].totalItemCount = source.totalItemCount
        if rowType == .continueWatching || rowType == .nextUp {
            dedupeNextUpAgainstContinueWatching()
        }

        let shouldRefreshTopShelf: Bool
        switch rowType {
        case .continueWatching:
            shouldRefreshTopShelf = true
        case .latestMedia:
            shouldRefreshTopShelf = true
        default:
            shouldRefreshTopShelf = false
        }

        if shouldRefreshTopShelf {
            refreshTopShelfCache()
        }
    }

    private func refreshTopShelfCache() {
        topShelfCacheWriter.write(
            rows: rows,
            posterImageURL: { [weak self] item in self?.posterImageUrl(for: item) },
            thumbImageURL: { [weak self] item in self?.thumbImageUrl(for: item) }
        )
    }

    private func reorderRowsBySection(_ sections: [HomeSectionType]) {
        var sectionOrder: [HomeSectionType: Int] = [:]
        for (index, section) in sections.enumerated() where sectionOrder[section] == nil {
            sectionOrder[section] = index
        }

        rows = rows.enumerated()
            .sorted { lhs, rhs in
                let lhsOrder = sectionOrder[homeSection(for: lhs.element.rowType)] ?? Int.max
                let rhsOrder = sectionOrder[homeSection(for: rhs.element.rowType)] ?? Int.max
                if lhsOrder == rhsOrder {
                    return lhs.offset < rhs.offset
                }
                return lhsOrder < rhsOrder
            }
            .map(\.element)
    }

    private func homeSection(for rowType: HomeRowType) -> HomeSectionType {
        switch rowType {
        case .continueWatching:
            return .resume
        case .nextUp:
            return .nextUp
        case .latestMedia:
            return .latestMedia
        case .myMedia:
            return .myMedia
        case .myMediaSmall:
            return .myMediaSmall
        case .resumeAudio:
            return .resumeAudio
        case .playlists:
            return .playlists
        case .liveTvButtons, .liveTvOnNow, .liveTvComingUp:
            return .liveTv
        }
    }

    private func filterHomeRowItems(_ items: [ServerItem], for rowType: HomeRowType) -> [ServerItem] {
        let parentalFiltered = container.parentalControlsRepository.filterItems(items)

        switch rowType {
        case .continueWatching, .nextUp, .latestMedia, .resumeAudio:
            return parentalFiltered.filter { $0.type != .boxSet }
        default:
            return parentalFiltered
        }
    }

    func loadMoreIfNeeded(row: HomeRow, currentIndex: Int) {
        guard let source = dataSources[row.id],
              source.shouldLoadMore(currentIndex: currentIndex),
              let client
        else { return }

        Task {
            let sourceClient = rowClients[row.id] ?? client
            await source.loadMore(client: sourceClient)
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
        if let parentTags = item.parentBackdropImageTags,
           let parentId = item.parentBackdropItemId,
           let tag = parentTags.first {
            return api.getItemImageUrl(
                itemId: parentId,
                imageType: .backdrop,
                maxWidth: 480,
                maxHeight: nil,
                tag: tag
            )
        }
        if let seriesId = item.seriesId {
            return api.getItemImageUrl(
                itemId: seriesId,
                imageType: .primary,
                maxWidth: 480,
                maxHeight: nil,
                tag: nil
            )
        }
        if let channelId = item.channelId {
            return api.getItemImageUrl(
                itemId: channelId,
                imageType: .primary,
                maxWidth: 480,
                maxHeight: nil,
                tag: nil
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
