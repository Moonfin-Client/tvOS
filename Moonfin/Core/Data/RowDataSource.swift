import Foundation

private let defaultRowChunkSize = 15

@MainActor
final class RowDataSource {
    let queryType: RowQueryType
    let changeTriggers: Set<ChangeTriggerType>
    let chunkSize: Int

    private(set) var items: [ServerItem] = []
    private(set) var totalItemCount = 0
    private(set) var isLoading = true
    private(set) var fullyLoaded = false
    private var isRetrieving = false
    private var lastRetrieve: Date?
    private var cachedItems: [ServerItem]?
    private let userPreferences = UserPreferences(store: UserDefaultsPreferenceStore())

    var sortBy: ItemSortBy?
    var sortOrder: SortOrder?
    var filters = FilterOptions()

    static let maxItems = 100
    private static let pluginDynamicFields: [ItemField] = [
        .overview,
        .genres,
        .providerIds,
        .mediaSources,
        .mediaStreams,
        .childCount,
    ]

    init(
        queryType: RowQueryType,
        changeTriggers: Set<ChangeTriggerType> = [],
        chunkSize: Int = defaultRowChunkSize
    ) {
        self.queryType = queryType
        self.changeTriggers = changeTriggers
        self.chunkSize = chunkSize
    }

    var isEmpty: Bool { items.isEmpty && !isLoading }

    func preload(_ preloadedItems: [ServerItem]) {
        items = preloadedItems
        totalItemCount = preloadedItems.count
        isLoading = false
        fullyLoaded = true
        lastRetrieve = Date()
    }

    // MARK: - Retrieve

    func retrieve(client: MediaServerClient) async {
        guard !isRetrieving else { return }
        isRetrieving = true
        isLoading = true
        fullyLoaded = false
        cachedItems = nil
        items = []

        defer {
            isRetrieving = false
            isLoading = false
            lastRetrieve = Date()
        }

        do {
            switch queryType {
            case .resume(let request):
                let result = try await client.itemsApi.getResumeItems(
                    request: paginatedResume(request, startIndex: 0)
                )
                items = result.items
                totalItemCount = result.totalRecordCount

            case .nextUp(let request):
                let result = try await client.itemsApi.getNextUp(
                    request: paginatedNextUp(request, startIndex: 0)
                )
                items = result.items
                totalItemCount = result.totalRecordCount

            case .mergedContinueWatching(let resumeRequest, let nextUpRequest):
                async let resumeTask = client.itemsApi.getResumeItems(
                    request: GetResumeItemsRequest(
                        userId: resumeRequest.userId,
                        parentId: resumeRequest.parentId,
                        includeItemTypes: resumeRequest.includeItemTypes,
                        excludeItemTypes: resumeRequest.excludeItemTypes,
                        mediaTypes: resumeRequest.mediaTypes,
                        fields: resumeRequest.fields,
                        limit: Self.maxItems,
                        startIndex: 0,
                        enableImages: resumeRequest.enableImages,
                        imageTypeLimit: resumeRequest.imageTypeLimit
                    )
                )
                async let nextUpTask = client.itemsApi.getNextUp(
                    request: GetNextUpRequest(
                        userId: nextUpRequest.userId,
                        seriesId: nextUpRequest.seriesId,
                        fields: nextUpRequest.fields,
                        limit: Self.maxItems,
                        startIndex: 0,
                        enableImages: nextUpRequest.enableImages,
                        imageTypeLimit: nextUpRequest.imageTypeLimit
                    )
                )

                let resumeResult = try await resumeTask
                let nextUpResult = try await nextUpTask

                let resumeIds = Set(resumeResult.items.map(\.id))

                var seriesLastPlayed: [String: Date] = [:]
                for item in resumeResult.items {
                    if let sid = item.seriesId, let date = item.userData?.lastPlayedDate {
                        if let existing = seriesLastPlayed[sid] {
                            if date > existing { seriesLastPlayed[sid] = date }
                        } else {
                            seriesLastPlayed[sid] = date
                        }
                    }
                }

                let dedupedNextUp = nextUpResult.items.filter { !resumeIds.contains($0.id) }
                let combined = resumeResult.items + dedupedNextUp

                items = combined.sorted { a, b in
                    let dateA = a.userData?.lastPlayedDate
                        ?? a.seriesId.flatMap { seriesLastPlayed[$0] }
                        ?? Date.distantPast
                    let dateB = b.userData?.lastPlayedDate
                        ?? b.seriesId.flatMap { seriesLastPlayed[$0] }
                        ?? Date.distantPast
                    return dateA > dateB
                }
                totalItemCount = items.count
                fullyLoaded = true

            case .latestMedia(let request):
                let allItems = try await client.itemsApi.getLatestMedia(request: request)
                cachedItems = allItems
                items = Array(allItems.prefix(chunkSize))
                totalItemCount = allItems.count

            case .items(let request):
                let result = try await client.itemsApi.getItems(
                    request: paginatedItems(request, startIndex: 0)
                )
                items = result.items
                totalItemCount = result.totalRecordCount

            case .pluginDynamic(let query):
                let allItems = try await loadPluginDynamicItems(query, client: client)
                cachedItems = allItems
                items = Array(allItems.prefix(chunkSize))
                totalItemCount = allItems.count

            case .similar(let itemId, let limit):
                let result = try await client.itemsApi.getSimilarItems(
                    itemId: itemId, limit: limit ?? chunkSize
                )
                items = result.items
                totalItemCount = result.totalRecordCount
                fullyLoaded = true

            case .seasons(let seriesId, let userId):
                let result = try await client.itemsApi.getSeasons(
                    seriesId: seriesId, userId: userId
                )
                items = result.items
                totalItemCount = result.totalRecordCount
                fullyLoaded = true

            case .episodes(let seriesId, let seasonId, let userId):
                let result = try await client.itemsApi.getEpisodes(
                    seriesId: seriesId, seasonId: seasonId, userId: userId
                )
                items = result.items
                totalItemCount = result.totalRecordCount
                fullyLoaded = true

            case .userViews(let userId):
                let views = try await client.userViewsApi.getUserViews(userId: userId)
                items = views
                totalItemCount = views.count
                fullyLoaded = true

            case .liveTvChannels:
                let result = try await client.liveTvApi.getChannels(
                    userId: client.userId, startIndex: 0, limit: chunkSize,
                    sortBy: nil, sortOrder: nil, isFavorite: nil, addCurrentProgram: nil
                )
                items = result.items
                totalItemCount = result.totalRecordCount

            case .liveTvOnNow:
                let result = try await client.liveTvApi.getRecommendedPrograms(
                    userId: client.userId, limit: chunkSize,
                    isAiring: true, hasAired: nil
                )
                items = result.items
                totalItemCount = result.totalRecordCount
                fullyLoaded = true

            case .liveTvComingUp:
                let result = try await client.liveTvApi.getRecommendedPrograms(
                    userId: client.userId, limit: chunkSize,
                    isAiring: nil, hasAired: false
                )
                items = result.items
                totalItemCount = result.totalRecordCount
                fullyLoaded = true

            case .liveTvRecordings:
                let result = try await client.liveTvApi.getRecordings(
                    channelId: nil, seriesTimerId: nil, startIndex: 0, limit: chunkSize
                )
                items = result.items
                totalItemCount = result.totalRecordCount

            case .staticItems(let staticItems):
                items = staticItems
                totalItemCount = staticItems.count
                fullyLoaded = true
            }

            if items.count >= totalItemCount { fullyLoaded = true }
        } catch {
            items = []
            totalItemCount = 0
        }
    }

    // MARK: - Load More

    func loadMore(client: MediaServerClient) async {
        guard !fullyLoaded, !isRetrieving else { return }
        isRetrieving = true
        defer { isRetrieving = false }

        let startIndex = items.count

        do {
            switch queryType {
            case .latestMedia, .pluginDynamic:
                guard let cached = cachedItems else { return }
                let end = min(startIndex + chunkSize, cached.count)
                guard end > startIndex else {
                    fullyLoaded = true
                    return
                }
                items.append(contentsOf: cached[startIndex..<end])

            case .resume(let request):
                let result = try await client.itemsApi.getResumeItems(
                    request: paginatedResume(request, startIndex: startIndex)
                )
                items.append(contentsOf: result.items)

            case .nextUp(let request):
                let result = try await client.itemsApi.getNextUp(
                    request: paginatedNextUp(request, startIndex: startIndex)
                )
                items.append(contentsOf: result.items)

            case .items(let request):
                let result = try await client.itemsApi.getItems(
                    request: paginatedItems(request, startIndex: startIndex)
                )
                items.append(contentsOf: result.items)

            case .liveTvChannels:
                let result = try await client.liveTvApi.getChannels(
                    userId: client.userId, startIndex: startIndex, limit: chunkSize,
                    sortBy: nil, sortOrder: nil, isFavorite: nil, addCurrentProgram: nil
                )
                items.append(contentsOf: result.items)

            case .liveTvRecordings:
                let result = try await client.liveTvApi.getRecordings(
                    channelId: nil, seriesTimerId: nil, startIndex: startIndex, limit: chunkSize
                )
                items.append(contentsOf: result.items)

            default:
                fullyLoaded = true
                return
            }

            if items.count >= totalItemCount { fullyLoaded = true }
        } catch { }
    }

    func shouldLoadMore(currentIndex: Int) -> Bool {
        let threshold = items.count - Int(Double(chunkSize) / 1.7)
        return currentIndex >= threshold
            && !fullyLoaded
            && !isRetrieving
            && items.count < Self.maxItems
    }

    // MARK: - Refresh

    func needsRefresh(service: DataRefreshService) -> Bool {
        guard let lastRetrieve else { return true }
        return changeTriggers.contains { trigger in
            guard let triggerDate = service.timestamp(for: trigger) else { return false }
            return triggerDate > lastRetrieve
        }
    }

    func refreshIfNeeded(client: MediaServerClient, service: DataRefreshService) async {
        guard needsRefresh(service: service) else { return }
        await retrieve(client: client)
    }

    // MARK: - Sorting & Filtering

    func updateSort(_ sort: ItemSortBy?, order: SortOrder?, client: MediaServerClient) async {
        sortBy = sort
        sortOrder = order
        await retrieve(client: client)
    }

    func updateFilters(_ newFilters: FilterOptions, client: MediaServerClient) async {
        filters = newFilters
        await retrieve(client: client)
    }

    // MARK: - Single Item Refresh

    func refreshItem(itemId: String, client: MediaServerClient) async {
        do {
            let updated = try await client.userLibraryApi.getItem(itemId: itemId)
            if let index = items.firstIndex(where: { $0.id == itemId }) {
                items[index] = updated
            }
        } catch { }
    }

    func removeItem(itemId: String) {
        items.removeAll { $0.id == itemId }
        totalItemCount = max(0, totalItemCount - 1)
    }

    // MARK: - Request Builders

    private func paginatedItems(_ base: GetItemsRequest, startIndex: Int) -> GetItemsRequest {
        GetItemsRequest(
            userId: base.userId,
            parentId: base.parentId,
            recursive: base.recursive,
            includeItemTypes: base.includeItemTypes,
            excludeItemTypes: base.excludeItemTypes,
            sortBy: sortBy.map { [$0, .sortName] } ?? base.sortBy,
            sortOrder: sortOrder ?? base.sortOrder,
            filters: filters.isEmpty ? base.filters : filters.itemFilters,
            fields: base.fields,
            searchTerm: base.searchTerm,
            limit: chunkSize,
            startIndex: startIndex,
            isFavorite: base.isFavorite,
            mediaTypes: base.mediaTypes,
            artistIds: base.artistIds,
            personIds: base.personIds,
            studioIds: base.studioIds,
            genres: base.genres,
            genreIds: base.genreIds,
            tags: base.tags,
            years: base.years,
            ids: base.ids,
            enableImages: base.enableImages,
            imageTypeLimit: base.imageTypeLimit,
            enableUserData: base.enableUserData,
            groupItems: base.groupItems,
            collapseBoxSetItems: base.collapseBoxSetItems,
            enableTotalRecordCount: base.enableTotalRecordCount
        )
    }

    private func paginatedResume(_ base: GetResumeItemsRequest, startIndex: Int) -> GetResumeItemsRequest {
        GetResumeItemsRequest(
            userId: base.userId,
            parentId: base.parentId,
            includeItemTypes: base.includeItemTypes,
            excludeItemTypes: base.excludeItemTypes,
            mediaTypes: base.mediaTypes,
            fields: base.fields,
            limit: chunkSize,
            startIndex: startIndex,
            enableImages: base.enableImages,
            imageTypeLimit: base.imageTypeLimit
        )
    }

    private func paginatedNextUp(_ base: GetNextUpRequest, startIndex: Int) -> GetNextUpRequest {
        GetNextUpRequest(
            userId: base.userId,
            seriesId: base.seriesId,
            fields: base.fields,
            limit: chunkSize,
            startIndex: startIndex,
            enableImages: base.enableImages,
            imageTypeLimit: base.imageTypeLimit
        )
    }

    private func loadPluginDynamicItems(_ query: DynamicHomeSectionQuery, client: MediaServerClient) async throws -> [ServerItem] {
        switch query.source {
        case .hss:
            return try await loadHssSectionItems(
                sectionType: query.sectionType,
                additionalData: query.additionalData,
                client: client
            )

        case .collections:
            return try await loadCollectionsItems(query: query, client: client)

        case .genres:
            return try await loadGenresItems(query: query, client: client)

        case .kefinTweaks:
            return try await loadKefinSectionItems(query: query, client: client)
        }
    }

    private func loadKefinSectionItems(query: DynamicHomeSectionQuery, client: MediaServerClient) async throws -> [ServerItem] {
        guard let spec = parseKefinSpec(query.additionalData),
              let result = try await runKefinSpec(spec, client: client) else {
            return []
        }
        return result.items
    }

    private func parseKefinSpec(_ rawSpec: String?) -> [String: Any]? {
        guard let rawSpec,
              let data = rawSpec.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return decoded
    }

    private func runKefinSpec(_ spec: [String: Any], client: MediaServerClient) async throws -> ItemsResult? {
        let kind = (spec["kind"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let limit = max(1, min((spec["limit"] as? NSNumber)?.intValue ?? 16, Self.maxItems))

        switch kind {
        case "recentlyreleasedmovies":
            return try await client.itemsApi.getItems(request: GetItemsRequest(
                recursive: true,
                includeItemTypes: [.movie],
                sortBy: [.premiereDate],
                sortOrder: .descending,
                fields: Self.pluginDynamicFields,
                limit: limit,
                enableImages: true,
                imageTypeLimit: 1,
                enableTotalRecordCount: true
            ))

        case "recentlyreleasedepisodes":
            return try await client.itemsApi.getItems(request: GetItemsRequest(
                recursive: true,
                includeItemTypes: [.episode],
                sortBy: [.premiereDate],
                sortOrder: .descending,
                fields: Self.pluginDynamicFields,
                limit: limit,
                enableImages: true,
                imageTypeLimit: 1,
                enableTotalRecordCount: true
            ))

        case "watchagain":
            return try await client.itemsApi.getItems(request: GetItemsRequest(
                recursive: true,
                includeItemTypes: [.movie, .series],
                sortBy: [.datePlayed],
                sortOrder: .descending,
                filters: [.isPlayed],
                fields: Self.pluginDynamicFields,
                limit: limit,
                enableImages: true,
                imageTypeLimit: 1,
                enableTotalRecordCount: true
            ))

        case "recentlyaddedinlibrary":
            return try await runKefinRecentlyAddedInLibrary(spec: spec, limit: limit, client: client)

        case "custom":
            return try await runKefinCustom(spec: spec, limit: limit, client: client)

        default:
            return nil
        }
    }

    private func runKefinRecentlyAddedInLibrary(
        spec: [String: Any],
        limit: Int,
        client: MediaServerClient
    ) async throws -> ItemsResult? {
        let libraryIds = ((spec["libraryIds"] as? [Any])?.compactMap {
            ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }) ?? []

        guard !libraryIds.isEmpty else {
            return nil
        }

        var mergedItems: [ServerItem] = []
        var seenItemIds = Set<String>()

        for libraryId in libraryIds {
            let latest = try await client.itemsApi.getLatestMedia(request: GetLatestMediaRequest(
                parentId: libraryId,
                fields: Self.pluginDynamicFields,
                limit: limit,
                groupItems: false,
                imageTypeLimit: 1
            ))

            for item in latest where seenItemIds.insert(item.id).inserted {
                mergedItems.append(item)
            }

            if mergedItems.count >= limit {
                break
            }
        }

        let trimmed = Array(mergedItems.prefix(limit))
        return ItemsResult(items: trimmed, totalRecordCount: trimmed.count, startIndex: 0)
    }

    private func runKefinCustom(
        spec: [String: Any],
        limit: Int,
        client: MediaServerClient
    ) async throws -> ItemsResult? {
        let type = (spec["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let source = (spec["source"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !source.isEmpty else {
            return nil
        }

        let includeItemTypes = kefinIncludeItemTypes(
            spec["includeItemTypes"],
            fallback: [.movie, .series]
        )
        let sortBy = [kefinSortBy(spec["sortBy"] as? String)]
        let sortOrder = kefinSortOrder(spec["sortOrderDirection"] as? String)

        switch type {
        case "tag":
            return try await client.itemsApi.getItems(request: GetItemsRequest(
                recursive: true,
                includeItemTypes: includeItemTypes,
                sortBy: sortBy,
                sortOrder: sortOrder,
                fields: Self.pluginDynamicFields,
                limit: limit,
                tags: [source],
                enableImages: true,
                imageTypeLimit: 1,
                enableTotalRecordCount: true
            ))

        case "genre":
            return try await client.itemsApi.getItems(request: GetItemsRequest(
                recursive: true,
                includeItemTypes: includeItemTypes,
                sortBy: sortBy,
                sortOrder: sortOrder,
                fields: Self.pluginDynamicFields,
                limit: limit,
                genres: [source],
                genreIds: [source],
                enableImages: true,
                imageTypeLimit: 1,
                enableTotalRecordCount: true
            ))

        case "parent", "collection", "playlist":
            return try await client.itemsApi.getItems(request: GetItemsRequest(
                parentId: source,
                recursive: true,
                includeItemTypes: includeItemTypes,
                sortBy: sortBy,
                sortOrder: sortOrder,
                fields: Self.pluginDynamicFields,
                limit: limit,
                enableImages: true,
                imageTypeLimit: 1,
                enableTotalRecordCount: true
            ))

        default:
            return nil
        }
    }

    private func kefinIncludeItemTypes(_ rawValue: Any?, fallback: [ItemType]) -> [ItemType] {
        guard let values = rawValue as? [Any] else { return fallback }
        let mapped = values.compactMap { value -> ItemType? in
            guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }

            switch raw.lowercased() {
            case "movie":
                return .movie
            case "series", "tvshow", "tvshows":
                return .series
            case "episode":
                return .episode
            case "season":
                return .season
            case "audio":
                return .audio
            case "musicalbum", "album":
                return .musicAlbum
            case "musicartist", "artist":
                return .musicArtist
            case "musicvideo":
                return .musicVideo
            case "playlist":
                return .playlist
            case "boxset", "collection":
                return .boxSet
            case "book":
                return .book
            case "photo":
                return .photo
            case "video":
                return .video
            default:
                return nil
            }
        }

        return mapped.isEmpty ? fallback : mapped
    }

    private func kefinSortBy(_ rawValue: String?) -> ItemSortBy {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "releasedate", "premieredate":
            return .premiereDate
        case "dateadded", "datecreated":
            return .dateCreated
        case "name", "sortname":
            return .sortName
        case "communityrating":
            return .communityRating
        case "criticrating":
            return .criticRating
        case "runtime":
            return .runtime
        case "datelastcontentadded":
            return .dateCreated
        case "random", nil, "":
            return .random
        default:
            return .random
        }
    }

    private func kefinSortOrder(_ rawValue: String?) -> SortOrder {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "descending":
            return .descending
        default:
            return .ascending
        }
    }

    private func loadHssSectionItems(
        sectionType: String,
        additionalData: String?,
        client: MediaServerClient
    ) async throws -> [ServerItem] {
        guard let api = client.homeScreenSectionsApi else { return [] }
        let result = try await api.getSectionItems(
            sectionType: sectionType,
            additionalData: additionalData
        )
        return await enrichHomeSectionItems(result.items, client: client)
    }

    private func enrichHomeSectionItems(_ sourceItems: [ServerItem], client: MediaServerClient) async -> [ServerItem] {
        guard !sourceItems.isEmpty else { return [] }

        let ids = Array(sourceItems.map(\.id).prefix(Self.maxItems))
        let request = GetItemsRequest(
            fields: Self.pluginDynamicFields,
            limit: ids.count,
            ids: ids,
            enableImages: true,
            imageTypeLimit: 1,
            enableTotalRecordCount: false
        )

        guard let result = try? await client.itemsApi.getItems(request: request) else {
            return sourceItems
        }

        var itemsById: [String: ServerItem] = [:]
        for item in result.items where itemsById[item.id] == nil {
            itemsById[item.id] = item
        }
        return sourceItems.map { itemsById[$0.id] ?? $0 }
    }

    private func loadCollectionsItems(query: DynamicHomeSectionQuery, client: MediaServerClient) async throws -> [ServerItem] {
        let collectionId = (query.additionalData ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collectionId.isEmpty else { return [] }

        let request = GetItemsRequest(
            parentId: collectionId,
            recursive: true,
            sortBy: [currentHomeSortBy(for: .collections), .sortName],
            sortOrder: .ascending,
            fields: Self.pluginDynamicFields,
            limit: Self.maxItems,
            enableImages: true,
            imageTypeLimit: 1,
            enableTotalRecordCount: true
        )
        let result = try await client.itemsApi.getItems(request: request)
        return result.items
    }

    private func loadGenresItems(query: DynamicHomeSectionQuery, client: MediaServerClient) async throws -> [ServerItem] {
        let genreToken = (query.additionalData ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !genreToken.isEmpty else { return [] }

        let request = GetItemsRequest(
            recursive: true,
            includeItemTypes: genresIncludeItemTypes(),
            excludeItemTypes: [.episode],
            sortBy: [currentHomeSortBy(for: .genres), .sortName],
            sortOrder: .ascending,
            fields: Self.pluginDynamicFields,
            limit: Self.maxItems,
            genres: [genreToken],
            genreIds: [genreToken],
            enableImages: true,
            imageTypeLimit: 1,
            enableTotalRecordCount: true
        )
        let result = try await client.itemsApi.getItems(request: request)
        return result.items
    }

    private func currentHomeSortBy(for source: DynamicHomeSectionSource) -> ItemSortBy {
        let homeSort: HomeRowSortBy

        switch source {
        case .collections:
            homeSort = userPreferences[UserPreferences.collectionsRowSortBy]
        case .genres:
            homeSort = userPreferences[UserPreferences.genresRowSortBy]
        case .hss, .kefinTweaks:
            homeSort = .name
        }

        switch homeSort {
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

    private func genresIncludeItemTypes() -> [ItemType]? {
        switch userPreferences[UserPreferences.genresRowItems] {
        case .movies:
            return [.movie]
        case .series:
            return [.series]
        case .both:
            return [.movie, .series]
        }
    }
}
