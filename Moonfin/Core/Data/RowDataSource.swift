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

    var sortBy: ItemSortBy?
    var sortOrder: SortOrder?
    var filters = FilterOptions()

    static let maxItems = 100

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
            case .latestMedia:
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
            tags: base.tags,
            years: base.years,
            ids: base.ids,
            enableImages: base.enableImages,
            imageTypeLimit: base.imageTypeLimit,
            enableUserData: base.enableUserData,
            groupItems: base.groupItems
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
}
