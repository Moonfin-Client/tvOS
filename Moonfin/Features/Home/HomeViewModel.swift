import SwiftUI
import Combine
import OSLog

@MainActor
final class HomeViewModel: ObservableObject {
    let infoState = HomeInfoState()
    @Published private(set) var rows: [HomeRow] = []
    private(set) var visibleRows: [HomeRow] = []
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
    private var myMediaSummaries: [String: String] = [:]
    private var myMediaSummaryTasks: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let topShelfCacheWriter = TopShelfCacheWriter()
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "HomeViewModel")
    private static let selectionDebounceMs: UInt64 = 150_000_000
    private static let backdropDebounceMs: UInt64 = 200_000_000
    private static let chunkSize = 15
    private static let multiServerLimit = 30

    private static let defaultFields: [ItemField] = [
        .overview, .genres, .providerIds, .mediaSources, .mediaStreams, .childCount
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

        $rows
            .sink { [weak self] newRows in
                self?.visibleRows = newRows.filter { !$0.isEmpty }
            }
            .store(in: &cancellables)

        container.pluginSyncService.$syncCompletedCount
            .dropFirst()
            .filter { $0 > 0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadContent(forceReload: true, preserveExisting: true)
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

    private func client(for item: ServerItem) -> MediaServerClient? {
        if let serverId = item.effectiveServerId,
           let serverUUID = UUID(uuidString: serverId),
           let server = container.serverRepository.storedServers.value.first(where: { $0.id == serverUUID }) {
            return container.serverClientFactory.client(for: server)
        }
        return client
    }

    private var reloadQueuedWhileLoading = false
    private var queuedReloadForce = false
    private var queuedReloadPreserveExisting = true

    func loadContent(forceReload: Bool = false, preserveExisting: Bool = false) {
        if loadTask != nil {
            reloadQueuedWhileLoading = true
            queuedReloadForce = queuedReloadForce || forceReload
            queuedReloadPreserveExisting = queuedReloadPreserveExisting && preserveExisting
            return
        }

        guard forceReload || isInitialLoad else {
            refreshContent()
            return
        }

        reloadQueuedWhileLoading = false
        queuedReloadForce = false
        queuedReloadPreserveExisting = true

        loadTask?.cancel()
        loadTask = Task {
            defer { finishLoad() }
            guard let client else {
                await mediaBarViewModel.load()
                rows = []
                isInitialLoad = false
                return
            }

            let configs = activeHomeSectionConfigs()
            let builtinSections = builtinSections(from: configs)

            if multiServerActive {
                await loadMultiServerContent(sections: builtinSections, client: client)
                return
            }

            let viewDependent: Set<HomeSectionType> = [.latestMedia, .myMedia, .myMediaSmall]
            let needsViews = mediaBarViewModel.isEnabled
                || configs.contains(where: { $0.isBuiltin && viewDependent.contains($0.type) })

            let existingRows = rows

            dataSources = [:]
            rowClients = [:]
            var earlyRows: [HomeRow] = []
            for config in configs where !(config.isBuiltin && viewDependent.contains(config.type)) {
                earlyRows.append(contentsOf: buildRowDefinitions(for: config))
            }
            rows = preserveExisting
                ? reconciledRows(placeholders: earlyRows, existing: existingRows)
                : earlyRows
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

            let lateRows = configs
                .filter { $0.isBuiltin && viewDependent.contains($0.type) }
                .flatMap { buildRowDefinitions(for: $0) }
            if !lateRows.isEmpty {
                let rowsToAppend = preserveExisting
                    ? reconciledRows(placeholders: lateRows, existing: existingRows)
                    : lateRows
                rows.append(contentsOf: rowsToAppend)
                reorderRowsByConfigOrder(configs)
                let lateRowIds = Set(dataSources.keys).subtracting(earlyRowIds)
                await loadRows(lateRowIds, client: client)
            } else {
                reorderRowsByConfigOrder(configs)
            }

            ensureFallbackLibraryRowIfNeeded()

            refreshTopShelfCache()

            indexForSpotlight()
        }
    }

    private func finishLoad() {
        loadTask = nil
        if reloadQueuedWhileLoading {
            let forceReload = queuedReloadForce
            let preserveExisting = queuedReloadPreserveExisting

            reloadQueuedWhileLoading = false
            queuedReloadForce = false
            queuedReloadPreserveExisting = true

            loadContent(forceReload: forceReload, preserveExisting: preserveExisting)
        }
    }

    private func reconciledRows(placeholders: [HomeRow], existing: [HomeRow]) -> [HomeRow] {
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        return placeholders.map { placeholder in
            guard let current = existingById[placeholder.id] else {
                return placeholder
            }

            return HomeRow(
                id: placeholder.id,
                title: placeholder.title,
                items: current.items,
                rowType: placeholder.rowType,
                isMusicLibraryRow: placeholder.isMusicLibraryRow,
                isLoading: current.isLoading,
                totalItemCount: current.totalItemCount
            )
        }
    }

    private func scheduleMyMediaSummaryLoad(for item: ServerItem) {
        guard item.collectionType != nil else { return }
        guard myMediaSummaries[item.id] == nil else { return }
        guard myMediaSummaryTasks[item.id] == nil else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { myMediaSummaryTasks[item.id] = nil }
            guard let summary = await loadMyMediaSummary(for: item) else { return }
            myMediaSummaries[item.id] = summary
            if infoState.selectedItemState.item?.id == item.id {
                infoState.selectedItemState.metadataSummary = summary
            }
        }
        myMediaSummaryTasks[item.id] = task
    }

    private func loadMyMediaSummary(for item: ServerItem) async -> String? {
        guard let client = client(for: item) else { return nil }

        let queries = itemTypesForLibrary(item)
        var parts: [String] = []
        for (type, singular, plural) in queries {
            let count = await countItems(in: item.id, type: type, client: client)
            appendSummaryPart(&parts, count: count, singular: singular, plural: plural)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " \u{2022} ")
    }

    private func itemTypesForLibrary(_ item: ServerItem) -> [(ItemType, String, String)] {
        switch item.collectionType?.lowercased() {
        case "movies":
            return [(.movie, "movie", "movies"), (.boxSet, "collection", "collections")]
        case "tvshows":
            return [(.series, "series", "series"), (.season, "season", "seasons")]
        case "music":
            return [(.musicAlbum, "album", "albums"), (.audio, "track", "tracks")]
        case "photos", "homevideos":
            return [(.photo, "photo", "photos")]
        case "boxsets":
            return [(.boxSet, "collection", "collections")]
        case "playlists":
            return [(.playlist, "playlist", "playlists")]
        case "books":
            return [(.book, "book", "books")]
        default:
            return [
                (.movie, "movie", "movies"),
                (.series, "series", "series"),
                (.musicAlbum, "album", "albums"),
                (.audio, "track", "tracks"),
                (.photo, "photo", "photos"),
            ]
        }
    }

    private func countItems(in parentId: String, type: ItemType, client: MediaServerClient) async -> Int {
        do {
            let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                parentId: parentId,
                recursive: true,
                includeItemTypes: [type],
                limit: 1,
                startIndex: 0,
                enableTotalRecordCount: true
            ))
            return result.totalRecordCount
        } catch {
            return 0
        }
    }

    private func appendSummaryPart(
        _ parts: inout [String],
        count: Int,
        singular: String,
        plural: String
    ) {
        guard count > 0 else { return }
        let label = count == 1 ? singular : plural
        parts.append("\(count) \(label)")
    }

    func toggleWatched(_ item: ServerItem) {
        Task {
            let newValue = !(item.userData?.played ?? false)
            do {
                _ = try await container.itemMutationService.setPlayed(itemId: item.id, isPlayed: newValue)
                switch item.type {
                case .movie, .video, .trailer:
                    container.dataRefreshService.recordMoviePlayback()
                case .audio:
                    container.dataRefreshService.recordPlayback()
                default:
                    container.dataRefreshService.recordTvPlayback()
                }
                refreshContent()
            } catch {
                logger.error("Failed to toggle watched for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func toggleFavorite(_ item: ServerItem) {
        Task {
            let newValue = !(item.userData?.isFavorite ?? false)
            do {
                _ = try await container.itemMutationService.setFavorite(itemId: item.id, isFavorite: newValue)
                container.dataRefreshService.recordFavoriteUpdate()
                refreshContent()
            } catch {
                logger.error("Failed to toggle favorite for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
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
                        let isMusic = lib.library.collectionType?.lowercased() == "music"
                        let queryType: RowQueryType = isMusic
                            ? latestMusicQuery(parentId: lib.library.id)
                            : .latestMedia(latestMediaRequest(
                                parentId: lib.library.id,
                                collectionType: lib.library.collectionType
                            ))
                        resultRows.append(makeRow(
                            id: rowId,
                            title: "Latest \(lib.displayName)",
                            rowType: .latestMedia(libraryId: lib.library.id),
                            isMusicLibraryRow: isMusic,
                            queryType: queryType,
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
        let filtered = filterHomeRowItems(items, for: rowType, rowId: id)
        let source = RowDataSource(queryType: .staticItems(filtered), changeTriggers: [], chunkSize: Self.chunkSize)
        source.preload(filtered)
        dataSources[id] = source
        return HomeRow(id: id, title: title, items: filtered, rowType: rowType, isMusicLibraryRow: isMusicLibraryRow, isLoading: false, totalItemCount: filtered.count)
    }

    private func activeHomeSectionConfigs() -> [HomeSectionConfig] {
        let scoped = container.userPreferences.activeHomeSectionConfigs.filter {
            isConfigVisibleForCurrentServer($0) && isConfigEnabledByPreferences($0)
        }
        return deduplicatedHomeSectionConfigs(scoped)
    }

    private func builtinSections(from configs: [HomeSectionConfig]) -> [HomeSectionType] {
        var seen = Set<HomeSectionType>()
        var result: [HomeSectionType] = []
        for config in configs where config.isBuiltin && config.type != .none && config.type != .mediaBar {
            guard seen.insert(config.type).inserted else { continue }
            result.append(config.type)
        }
        return result
    }

    private func isConfigVisibleForCurrentServer(_ config: HomeSectionConfig) -> Bool {
        guard config.isPluginDynamic else { return true }
        guard let serverId = normalizedOptionalKey(config.serverId) else { return true }
        return currentServerIdentifiers().contains(serverId)
    }

    private func currentServerIdentifiers() -> Set<String> {
        var ids = Set<String>()

        if let server = container.serverRepository.currentServer.value {
            ids.insert(normalizedServerIdentifier(server.id.uuidString))
            ids.insert(normalizedServerIdentifier(server.address))
        }

        if let baseURL = client?.baseURL?.absoluteString {
            ids.insert(normalizedServerIdentifier(baseURL))
        }

        return ids
    }

    private func normalizedServerIdentifier(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private func normalizedOptionalKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalizedServerIdentifier(value)
        return normalized.isEmpty ? nil : normalized
    }

    private func isConfigEnabledByPreferences(_ config: HomeSectionConfig) -> Bool {
        guard config.isPluginDynamic else {
            switch config.type {
            case .none, .mediaBar:
                return false
            case .favorites,
                .favoriteMovies,
                .favoriteSeries,
                .favoriteEpisodes,
                .favoritePeople,
                .favoriteArtists,
                .favoriteMusicVideos,
                .favoriteAlbums,
                .favoriteSongs:
                return container.userPreferences[UserPreferences.displayFavoritesRows]
            case .collections:
                return false
            case .genres:
                return false
            default:
                return true
            }
        }

        switch config.pluginSource {
        case .collections:
            return container.userPreferences[UserPreferences.displayCollectionsRows]
        case .genres:
            return container.userPreferences[UserPreferences.displayGenresRows]
        case .hss, .kefinTweaks:
            return true
        }
    }

    private func deduplicatedHomeSectionConfigs(_ configs: [HomeSectionConfig]) -> [HomeSectionConfig] {
        var seenBuiltin = Set<HomeSectionType>()
        var builtinConfigs: [HomeSectionConfig] = []
        for config in configs where config.isBuiltin && config.type != .none && config.type != .mediaBar {
            guard seenBuiltin.insert(config.type).inserted else { continue }
            builtinConfigs.append(config)
        }

        var builtinDuplicateKeys = Set<String>()
        for config in builtinConfigs {
            builtinDuplicateKeys.formUnion(duplicateKeysForBuiltin(config.type))
        }

        var seenPluginStableIds = Set<String>()
        var seenPluginDuplicateKeys = Set<String>()
        var pluginConfigs: [HomeSectionConfig] = []

        for config in configs where config.isPluginDynamic {
            guard seenPluginStableIds.insert(config.stableId).inserted else { continue }
            let keys = duplicateKeysForPluginConfig(config)
            if !keys.isDisjoint(with: builtinDuplicateKeys) { continue }
            if !keys.isDisjoint(with: seenPluginDuplicateKeys) { continue }
            seenPluginDuplicateKeys.formUnion(keys)
            pluginConfigs.append(config)
        }

        return (builtinConfigs + pluginConfigs).sorted { $0.order < $1.order }
    }

    private func duplicateKeysForBuiltin(_ section: HomeSectionType) -> Set<String> {
        switch section {
        case .resume:
            return ["resume"]
        case .resumeBook:
            return ["resumeBook"]
        case .nextUp:
            return ["nextUp"]
        case .latestMedia:
            return ["latestMedia"]
        case .activeRecordings:
            return ["activeRecordings"]
        case .recentlyReleased:
            return ["recentlyReleased"]
        case .favorites:
            return ["favorites"]
        case .favoriteMovies:
            return ["favoriteMovies"]
        case .favoriteSeries:
            return ["favoriteSeries"]
        case .favoriteEpisodes:
            return ["favoriteEpisodes"]
        case .favoritePeople:
            return ["favoritePeople"]
        case .favoriteArtists:
            return ["favoriteArtists"]
        case .favoriteMusicVideos:
            return ["favoriteMusicVideos"]
        case .favoriteAlbums:
            return ["favoriteAlbums"]
        case .favoriteSongs:
            return ["favoriteSongs"]
        case .collections:
            return ["collections"]
        case .genres:
            return ["genres"]
        case .myMedia:
            return ["libraryTiles"]
        case .myMediaSmall:
            return ["libraryButtons"]
        case .resumeAudio:
            return ["resumeAudio"]
        case .playlists:
            return ["playlists"]
        case .liveTv:
            return ["liveTv"]
        case .mediaBar:
            return []
        case .none:
            return []
        }
    }

    private func duplicateKeysForPluginConfig(_ config: HomeSectionConfig) -> Set<String> {
        switch config.pluginSource {
        case .hss:
            return duplicateKeysForHssSection(config.pluginSection)
        case .kefinTweaks:
            return duplicateKeysForKefinSection(config.pluginSection, additionalData: config.pluginAdditionalData)
        case .collections:
            guard let key = normalizedOptionalKey(config.pluginAdditionalData) else { return [] }
            return ["collections:\(key)"]
        case .genres:
            guard let key = normalizedOptionalKey(config.pluginAdditionalData) else { return [] }
            return ["genres:\(key)"]
        }
    }

    private func duplicateKeysForHssSection(_ section: String?) -> Set<String> {
        switch normalizedSectionToken(section) {
        case "resume", "continuewatching":
            return duplicateKeysForBuiltin(.resume)
        case "resumebook", "continuereading":
            return duplicateKeysForBuiltin(.resumeBook)
        case "nextup":
            return duplicateKeysForBuiltin(.nextUp)
        case "activerecordings", "recordings":
            return duplicateKeysForBuiltin(.activeRecordings)
        case "recentlyreleased", "recentlyreleasedmovies", "recentlyreleasedepisodes":
            return duplicateKeysForBuiltin(.recentlyReleased)
        case "latest", "latestmedia", "recentlyadded", "recentlyaddedinlibrary":
            return duplicateKeysForBuiltin(.latestMedia)
        case "favorites", "favoriteitems":
            return duplicateKeysForBuiltin(.favorites)
        case "favoritemovies", "favoritemovie":
            return duplicateKeysForBuiltin(.favoriteMovies)
        case "favoriteseries", "favoriteshows", "favoritetvshows":
            return duplicateKeysForBuiltin(.favoriteSeries)
        case "favoriteepisodes", "favoriteepisode":
            return duplicateKeysForBuiltin(.favoriteEpisodes)
        case "favoritepeople", "favoriteperson":
            return duplicateKeysForBuiltin(.favoritePeople)
        case "favoriteartists", "favoriteartist":
            return duplicateKeysForBuiltin(.favoriteArtists)
        case "favoritemusicvideos", "favoritemusicvideo":
            return duplicateKeysForBuiltin(.favoriteMusicVideos)
        case "favoritealbums", "favoritealbum":
            return duplicateKeysForBuiltin(.favoriteAlbums)
        case "favoritesongs", "favoritesong":
            return duplicateKeysForBuiltin(.favoriteSongs)
        case "resumeaudio", "continuelistening":
            return duplicateKeysForBuiltin(.resumeAudio)
        case "playlists", "watchlist":
            return duplicateKeysForBuiltin(.playlists)
        case "livetv":
            return duplicateKeysForBuiltin(.liveTv)
        case "collections", "collection":
            return duplicateKeysForBuiltin(.collections)
        case "genres", "genre":
            return duplicateKeysForBuiltin(.genres)
        case "mymedia", "librarytiles":
            return duplicateKeysForBuiltin(.myMedia)
        case "mymediasmall", "librarybuttons":
            return duplicateKeysForBuiltin(.myMediaSmall)
        default:
            return []
        }
    }

    private func duplicateKeysForKefinSection(_ section: String?, additionalData: String?) -> Set<String> {
        let token = normalizedSectionToken(kefinKind(section: section, additionalData: additionalData))
        if token.contains("recentlyreleased") {
            return duplicateKeysForBuiltin(.recentlyReleased)
        }
        if token.contains("recentlyadded") {
            return duplicateKeysForBuiltin(.latestMedia)
        }
        if token.contains("watchagain") || token.contains("continuewatching") {
            return duplicateKeysForBuiltin(.resume)
        }
        if token.contains("nextup") {
            return duplicateKeysForBuiltin(.nextUp)
        }
        return []
    }

    private func kefinKind(section: String?, additionalData: String?) -> String? {
        if let additionalData,
           let data = additionalData.data(using: .utf8),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let kind = raw["kind"] as? String,
           !kind.isEmpty {
            return kind
        }

        guard let section, !section.isEmpty else { return nil }
        if let idx = section.firstIndex(of: ":") {
            let next = section.index(after: idx)
            if next < section.endIndex {
                return String(section[next...])
            }
        }
        return section
    }

    private func normalizedSectionToken(_ value: String?) -> String {
        let raw = (value ?? "").lowercased()
        let parts = raw.split { !$0.isLetter && !$0.isNumber }
        return parts.joined()
    }

    private func buildRowDefinitions(for config: HomeSectionConfig) -> [HomeRow] {
        if config.isPluginDynamic {
            return buildPluginDynamicRows(for: config)
        }
        return buildRowDefinitions(for: config.type)
    }

    private func buildPluginDynamicRows(for config: HomeSectionConfig) -> [HomeRow] {
        let sectionType = (config.pluginSection ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sectionType.isEmpty else { return [] }

        let title = (config.pluginDisplayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rowTitle = title.isEmpty ? sectionType : title

        let query = DynamicHomeSectionQuery(
            source: dynamicSource(for: config.pluginSource),
            sectionType: sectionType,
            additionalData: config.pluginAdditionalData
        )

        return [makeRow(
            id: config.stableId,
            title: rowTitle,
            rowType: .latestMedia(libraryId: config.stableId),
            queryType: .pluginDynamic(query),
            triggers: [.libraryUpdated]
        )]
    }

    private func dynamicSource(for pluginSource: HomeSectionPluginSource) -> DynamicHomeSectionSource {
        switch pluginSource {
        case .hss:
            return .hss
        case .kefinTweaks:
            return .kefinTweaks
        case .collections:
            return .collections
        case .genres:
            return .genres
        }
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

        case .resumeBook:
            return [makeRow(
                id: "resume_books",
                title: "Continue Reading",
                rowType: .resumeBook,
                queryType: .resume(GetResumeItemsRequest(
                    mediaTypes: [.book],
                    fields: Self.defaultFields,
                    enableImages: true,
                    imageTypeLimit: 1
                )),
                triggers: [.libraryUpdated]
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
                let isMusic = view.collectionType?.lowercased() == "music"
                let queryType: RowQueryType = isMusic
                    ? latestMusicQuery(parentId: view.id)
                    : .latestMedia(latestMediaRequest(
                        parentId: view.id,
                        collectionType: view.collectionType
                    ))
                return makeRow(
                    id: "latest_\(view.id)",
                    title: "Latest \(view.name)",
                    rowType: .latestMedia(libraryId: view.id),
                    isMusicLibraryRow: isMusic,
                    queryType: queryType,
                    triggers: [.libraryUpdated]
                )
            }

        case .activeRecordings:
            return [makeRow(
                id: "active_recordings",
                title: "Active Recordings",
                rowType: .activeRecordings,
                queryType: .liveTvRecordings,
                triggers: []
            )]

        case .recentlyReleased:
            return [makeRow(
                id: "recently_released",
                title: "Recently Released",
                rowType: .recentlyReleased,
                queryType: .items(GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.movie, .episode],
                    sortBy: [.premiereDate],
                    sortOrder: .descending,
                    fields: Self.defaultFields,
                    limit: RowDataSource.maxItems,
                    enableImages: true,
                    imageTypeLimit: 1,
                    enableTotalRecordCount: true
                )),
                triggers: [.libraryUpdated]
            )]

        case .favorites,
            .favoriteMovies,
            .favoriteSeries,
            .favoriteEpisodes,
            .favoritePeople,
            .favoriteArtists,
            .favoriteMusicVideos,
            .favoriteAlbums,
            .favoriteSongs:
            guard let favoriteConfig = favoriteRowConfig(for: section) else {
                return []
            }

            return [makeRow(
                id: favoriteConfig.id,
                title: favoriteConfig.title,
                rowType: favoriteConfig.rowType,
                queryType: .items(GetItemsRequest(
                    recursive: true,
                    includeItemTypes: favoriteConfig.includeItemTypes,
                    sortBy: [sortByForHomeRow(container.userPreferences[UserPreferences.favoritesRowSortBy]), .sortName],
                    sortOrder: .ascending,
                    filters: [.isFavorite],
                    fields: Self.defaultFields,
                    limit: RowDataSource.maxItems,
                    enableImages: true,
                    imageTypeLimit: 1,
                    enableTotalRecordCount: true
                )),
                triggers: [.libraryUpdated]
            )]

        case .collections:
            return [makeRow(
                id: "collections_builtin",
                title: "Collections",
                rowType: .collections,
                queryType: .items(GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.boxSet],
                    sortBy: [sortByForHomeRow(container.userPreferences[UserPreferences.collectionsRowSortBy]), .sortName],
                    sortOrder: .ascending,
                    fields: Self.defaultFields,
                    limit: RowDataSource.maxItems,
                    enableImages: true,
                    imageTypeLimit: 1,
                    enableTotalRecordCount: true
                )),
                triggers: [.libraryUpdated]
            )]

        case .genres:
            return [makeRow(
                id: "genres_builtin",
                title: "Genres",
                rowType: .genres,
                queryType: .items(GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.genre],
                    sortBy: [.sortName],
                    sortOrder: .ascending,
                    fields: Self.defaultFields,
                    limit: RowDataSource.maxItems,
                    enableImages: true,
                    imageTypeLimit: 1,
                    enableTotalRecordCount: true
                )),
                triggers: [.libraryUpdated]
            )]

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

        case .mediaBar:
            return []

        case .none:
            return []
        }
    }

    private func latestMusicQuery(parentId: String) -> RowQueryType {
        .items(GetItemsRequest(
            parentId: parentId,
            recursive: true,
            includeItemTypes: [.musicAlbum],
            sortBy: [.dateCreated],
            sortOrder: .descending,
            fields: Self.defaultFields,
            limit: RowDataSource.maxItems,
            imageTypeLimit: 1
        ))
    }

    private func sortByForHomeRow(_ sortBy: HomeRowSortBy) -> ItemSortBy {
        switch sortBy {
        case .name:
            return .sortName
        case .dateAdded:
            return .dateCreated
        case .premiereDate:
            return .premiereDate
        case .rating:
            return .officialRating
        case .runtime:
            return .runtime
        case .random:
            return .random
        case .criticRating:
            return .criticRating
        case .communityRating:
            return .communityRating
        }
    }

    private func favoriteRowConfig(for section: HomeSectionType) -> (
        id: String,
        title: String,
        rowType: HomeRowType,
        includeItemTypes: [ItemType]?
    )? {
        switch section {
        case .favorites:
            return ("favorites", "Favorites", .favorites, nil)
        case .favoriteMovies:
            return ("favorite_movies", "Favorite Movies", .favoriteMovies, [.movie])
        case .favoriteSeries:
            return ("favorite_series", "Favorite Series", .favoriteSeries, [.series])
        case .favoriteEpisodes:
            return ("favorite_episodes", "Favorite Episodes", .favoriteEpisodes, [.episode])
        case .favoritePeople:
            return ("favorite_people", "Favorite People", .favoritePeople, [.person])
        case .favoriteArtists:
            return ("favorite_artists", "Favorite Artists", .favoriteArtists, [.musicArtist])
        case .favoriteMusicVideos:
            return ("favorite_music_videos", "Favorite Music Videos", .favoriteMusicVideos, [.musicVideo])
        case .favoriteAlbums:
            return ("favorite_albums", "Favorite Albums", .favoriteAlbums, [.musicAlbum])
        case .favoriteSongs:
            return ("favorite_songs", "Favorite Songs", .favoriteSongs, [.audio])
        default:
            return nil
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
            return [.photo]
        case "mixed":
            return [.movie, .series, .musicAlbum, .photo]
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
        let filtered = filterHomeRowItems(source.items, for: rowType, rowId: rowId)
        rows[index].items = filtered
        rows[index].isLoading = source.isLoading
        rows[index].totalItemCount = source.totalItemCount
        if rowType == .continueWatching || rowType == .nextUp {
            dedupeNextUpAgainstContinueWatching()
        }

        let shouldRefreshTopShelf: Bool
        switch rowType {
        case .continueWatching, .resumeBook:
            shouldRefreshTopShelf = true
        case .latestMedia,
            .activeRecordings,
            .recentlyReleased,
            .favorites,
            .favoriteMovies,
            .favoriteSeries,
            .favoriteEpisodes,
            .favoritePeople,
            .favoriteArtists,
            .favoriteMusicVideos,
            .favoriteAlbums,
            .favoriteSongs,
            .collections,
            .genres:
            shouldRefreshTopShelf = true
        default:
            shouldRefreshTopShelf = false
        }

        if shouldRefreshTopShelf {
            refreshTopShelfCache()
        }
    }

    private func refreshTopShelfCache() {
        let prefs = container.userPreferences
        let cwType = prefs[UserPreferences.homeImageTypeContinueWatching]
        let libType = prefs[UserPreferences.homeImageTypeLibraries]

        let displayType: (HomeRowType) -> ImageDisplayType = { rowType in
            switch rowType {
            case .continueWatching, .resumeBook: return cwType
            default: return libType
            }
        }

        topShelfCacheWriter.write(
            rows: rows,
            imageURL: { [weak self] item, rowType in
                guard let self else { return nil }
                switch displayType(rowType) {
                case .thumb, .banner:
                    return self.topShelfThumbImageUrl(for: item)
                default:
                    return self.topShelfPosterImageUrl(for: item)
                }
            },
            contentImageURL: { [weak self] item in
                self?.topShelfThumbImageUrl(for: item)
            }
        )
    }

    private func reorderRowsByConfigOrder(_ configs: [HomeSectionConfig]) {
        var builtinOrder: [HomeSectionType: Int] = [:]
        var pluginOrder: [String: Int] = [:]

        for (index, config) in configs.enumerated() {
            if config.isBuiltin {
                if builtinOrder[config.type] == nil {
                    builtinOrder[config.type] = index
                }
            } else {
                pluginOrder[config.stableId] = index
            }
        }

        rows = rows.enumerated()
            .sorted { lhs, rhs in
                let lhsOrder = orderForRow(
                    lhs.element,
                    builtinOrder: builtinOrder,
                    pluginOrder: pluginOrder
                )
                let rhsOrder = orderForRow(
                    rhs.element,
                    builtinOrder: builtinOrder,
                    pluginOrder: pluginOrder
                )

                if lhsOrder == rhsOrder {
                    return lhs.offset < rhs.offset
                }
                return lhsOrder < rhsOrder
            }
            .map(\.element)
    }

    private func orderForRow(
        _ row: HomeRow,
        builtinOrder: [HomeSectionType: Int],
        pluginOrder: [String: Int]
    ) -> Int {
        if let order = pluginOrder[row.id] {
            return order
        }

        if let mappedSection = builtinSectionForRowId(row.id),
           let mappedOrder = builtinOrder[mappedSection] {
            return mappedOrder
        }

        return builtinOrder[homeSection(for: row.rowType)] ?? Int.max
    }

    private func builtinSectionForRowId(_ rowId: String) -> HomeSectionType? {
        if rowId == "resume_video" || rowId == "merged_continue_watching" || rowId == "ms_resume_video" {
            return .resume
        }
        if rowId == "resume_books" {
            return .resumeBook
        }
        if rowId == "next_up" || rowId == "ms_next_up" {
            return .nextUp
        }
        if rowId == "active_recordings" {
            return .activeRecordings
        }
        if rowId == "recently_released" {
            return .recentlyReleased
        }
        if rowId == "favorites" {
            return .favorites
        }
        if rowId == "favorite_movies" {
            return .favoriteMovies
        }
        if rowId == "favorite_series" {
            return .favoriteSeries
        }
        if rowId == "favorite_episodes" {
            return .favoriteEpisodes
        }
        if rowId == "favorite_people" {
            return .favoritePeople
        }
        if rowId == "favorite_artists" {
            return .favoriteArtists
        }
        if rowId == "favorite_music_videos" {
            return .favoriteMusicVideos
        }
        if rowId == "favorite_albums" {
            return .favoriteAlbums
        }
        if rowId == "favorite_songs" {
            return .favoriteSongs
        }
        if rowId == "collections_builtin" {
            return .collections
        }
        if rowId == "genres_builtin" {
            return .genres
        }
        if rowId == "my_media" || rowId == "ms_my_media" {
            return .myMedia
        }
        if rowId == "my_media_small" || rowId == "ms_my_media_small" {
            return .myMediaSmall
        }
        if rowId == "resume_audio" {
            return .resumeAudio
        }
        if rowId == "playlists" {
            return .playlists
        }
        if rowId == "live_tv_buttons" || rowId == "live_tv_on_now" || rowId == "live_tv_coming_up" {
            return .liveTv
        }
        if rowId.hasPrefix("latest_") || rowId.hasPrefix("ms_latest_") {
            return .latestMedia
        }
        return nil
    }

    private func homeSection(for rowType: HomeRowType) -> HomeSectionType {
        switch rowType {
        case .continueWatching:
            return .resume
        case .resumeBook:
            return .resumeBook
        case .nextUp:
            return .nextUp
        case .latestMedia:
            return .latestMedia
        case .activeRecordings:
            return .activeRecordings
        case .recentlyReleased:
            return .recentlyReleased
        case .favorites:
            return .favorites
        case .favoriteMovies:
            return .favoriteMovies
        case .favoriteSeries:
            return .favoriteSeries
        case .favoriteEpisodes:
            return .favoriteEpisodes
        case .favoritePeople:
            return .favoritePeople
        case .favoriteArtists:
            return .favoriteArtists
        case .favoriteMusicVideos:
            return .favoriteMusicVideos
        case .favoriteAlbums:
            return .favoriteAlbums
        case .favoriteSongs:
            return .favoriteSongs
        case .collections:
            return .collections
        case .genres:
            return .genres
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
        case .mediaBar:
            return .mediaBar
        case .none:
            return .none
        }
    }

    private func filterHomeRowItems(_ items: [ServerItem], for rowType: HomeRowType, rowId: String? = nil) -> [ServerItem] {
        let parentalFiltered = container.parentalControlsRepository.filterItems(items)

        switch rowType {
        case .continueWatching, .resumeBook, .nextUp, .resumeAudio:
            return parentalFiltered.filter { $0.type != .boxSet }
        case .latestMedia:
            if let rowId,
               (rowId == "collections_builtin" || rowId.hasPrefix("pluginDynamic:collections:")) {
                return parentalFiltered
            }
            return parentalFiltered.filter { $0.type != .boxSet }
        case .activeRecordings,
            .recentlyReleased,
            .favorites,
            .favoriteMovies,
            .favoriteSeries,
            .favoriteEpisodes,
            .favoritePeople,
            .favoriteArtists,
            .favoriteMusicVideos,
            .favoriteAlbums,
            .favoriteSongs,
            .genres:
            return parentalFiltered.filter { $0.type != .boxSet }
        case .collections:
            return parentalFiltered
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
            infoState.selectedItemState = .empty
            backgroundService.clearBackground()
            return
        }

        let isHomeRowsV2Mode = container.userPreferences[UserPreferences.homeRowsStyle] == .v2

        selectionDebounceTask?.cancel()
        selectionDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.selectionDebounceMs)
            guard !Task.isCancelled else { return }

            if isHomeRowsV2Mode {
                if infoState.selectedItemState != .empty {
                    infoState.selectedItemState = .empty
                }
                mediaBarRatingsViewModel.loadRatings(for: item)
                return
            }

            scheduleMyMediaSummaryLoad(for: item)
            infoState.selectedItemState = buildSelectedState(for: item)
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

        if let seriesId = item.seriesId {
            let useSeriesImage = container.userPreferences[UserPreferences.homeImageUseSeriesImage]
            if !useSeriesImage, let tag = item.imageTags?["Primary"] {
                return api.getItemImageUrl(
                    itemId: item.id,
                    imageType: .primary,
                    maxWidth: 300,
                    maxHeight: nil,
                    tag: tag
                )
            }
            return api.getItemImageUrl(
                itemId: seriesId,
                imageType: .primary,
                maxWidth: 300,
                maxHeight: nil,
                tag: item.seriesPrimaryImageTag
            )
        }

        let tag = item.imageTags?["Primary"]
        if tag == nil && item.type == .musicAlbum { return nil }
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
        let useSeriesImage = item.seriesId != nil
            ? container.userPreferences[UserPreferences.homeImageUseSeriesImage]
            : true

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
        if useSeriesImage {
            if let tag = item.parentThumbImageTag,
               let parentId = item.parentThumbItemId {
                return api.getItemImageUrl(
                    itemId: parentId,
                    imageType: .thumb,
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
                    tag: item.seriesPrimaryImageTag
                )
            }
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

    func bannerImageUrl(for item: ServerItem) -> String? {
        return thumbImageUrl(for: item)
    }

    private func topShelfPosterImageUrl(for item: ServerItem) -> String? {
        guard let api = imageApi(for: item) else { return nil }

        if let seriesId = item.seriesId {
            let useSeriesImage = container.userPreferences[UserPreferences.homeImageUseSeriesImage]
            if !useSeriesImage, let tag = item.imageTags?["Primary"] {
                return api.getItemImageUrl(
                    itemId: item.id,
                    imageType: .primary,
                    maxWidth: 800,
                    maxHeight: nil,
                    tag: tag
                )
            }
            return api.getItemImageUrl(
                itemId: seriesId,
                imageType: .primary,
                maxWidth: 800,
                maxHeight: nil,
                tag: item.seriesPrimaryImageTag
            )
        }

        let tag = item.imageTags?["Primary"]
        return api.getItemImageUrl(
            itemId: item.id,
            imageType: .primary,
            maxWidth: 800,
            maxHeight: nil,
            tag: tag
        )
    }

    private func topShelfThumbImageUrl(for item: ServerItem) -> String? {
        guard let api = imageApi(for: item) else { return nil }
        if let tag = item.imageTags?["Thumb"] {
            return api.getItemImageUrl(
                itemId: item.id,
                imageType: .thumb,
                maxWidth: 1920,
                maxHeight: nil,
                tag: tag
            )
        }
        if let tag = item.parentThumbImageTag,
           let parentId = item.parentThumbItemId {
            return api.getItemImageUrl(
                itemId: parentId,
                imageType: .thumb,
                maxWidth: 1920,
                maxHeight: nil,
                tag: tag
            )
        }
        if let tags = item.backdropImageTags, let tag = tags.first {
            return api.getItemImageUrl(
                itemId: item.id,
                imageType: .backdrop,
                maxWidth: 1920,
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
                maxWidth: 1920,
                maxHeight: nil,
                tag: tag
            )
        }
        if let seriesId = item.seriesId {
            return api.getItemImageUrl(
                itemId: seriesId,
                imageType: .primary,
                maxWidth: 1920,
                maxHeight: nil,
                tag: item.seriesPrimaryImageTag
            )
        }
        if let channelId = item.channelId {
            return api.getItemImageUrl(
                itemId: channelId,
                imageType: .primary,
                maxWidth: 1920,
                maxHeight: nil,
                tag: nil
            )
        }
        let tag = item.imageTags?["Primary"]
        return api.getItemImageUrl(
            itemId: item.id,
            imageType: .primary,
            maxWidth: 1920,
            maxHeight: nil,
            tag: tag
        )
    }

    private func buildSelectedState(for item: ServerItem) -> SelectedItemState {
        SelectedItemState(
            title: item.name,
            summary: item.overview ?? "",
            item: item,
            logoUrl: logoImageUrl(for: item),
            backdropUrl: backdropUrls(for: item).first,
            metadataSummary: myMediaSummaries[item.id]
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
