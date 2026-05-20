import SwiftUI
import Combine

@MainActor
final class MediaBarViewModel: ObservableObject {
    @Published private(set) var state: MediaBarState = .loading
    @Published private(set) var currentIndex: Int = 0
    private(set) var isFocused: Bool = false
    private var isPaused: Bool = false

    private let container: AppContainer
    private var autoAdvanceTimer: AnyCancellable?
    private var preferencesObserver: NSObjectProtocol?
    private var preferencesChangeCancellable: AnyCancellable?
    private var preferenceChangeTask: Task<Void, Never>?
    private var preferenceReloadTask: Task<Void, Never>?
    private var loadTime: Date?
    private var lastUserViews: [ServerItem] = []
    private static let staleThreshold: TimeInterval = 300

    private struct ReloadPreferenceSnapshot: Equatable {
        let mode: MediaBarMode
        let contentType: MediaBarContentType
        let itemCount: MediaBarItemCount
        let libraryIds: [String]
        let collectionIds: [String]
        let excludedGenres: [String]
    }

    private struct TimerPreferenceSnapshot: Equatable {
        let autoAdvance: Bool
        let intervalMs: Int
    }

    private var reloadPreferenceSnapshot: ReloadPreferenceSnapshot
    private var timerPreferenceSnapshot: TimerPreferenceSnapshot

    var isStale: Bool {
        guard let loadTime else { return true }
        return Date().timeIntervalSince(loadTime) > Self.staleThreshold
    }

    static let fetchFields: [ItemField] = [.overview, .genres, .providerIds]

    var currentItem: MediaBarSlideItem? {
        guard case .ready(let items) = state, !items.isEmpty else { return nil }
        return items[currentIndex]
    }

    var currentItemBackdropUrl: String? {
        currentItem?.backdropUrl
    }

    var isEnabled: Bool {
        let enabled = container.userPreferences[UserPreferences.mediaBarEnabled]
        let mode = container.userPreferences[UserPreferences.mediaBarMode]
        return enabled && mode != .off
    }

    init(container: AppContainer) {
        self.container = container
        let prefs = container.userPreferences
        self.reloadPreferenceSnapshot = ReloadPreferenceSnapshot(
            mode: prefs[UserPreferences.mediaBarMode],
            contentType: prefs[UserPreferences.mediaBarContentType],
            itemCount: prefs[UserPreferences.mediaBarItemCount],
            libraryIds: Self.normalizedIds(prefs[UserPreferences.mediaBarLibraryIds]),
            collectionIds: Self.normalizedIds(prefs[UserPreferences.mediaBarCollectionIds]),
            excludedGenres: Self.normalizedGenres(prefs[UserPreferences.mediaBarExcludedGenres])
        )
        self.timerPreferenceSnapshot = TimerPreferenceSnapshot(
            autoAdvance: prefs[UserPreferences.mediaBarAutoAdvance],
            intervalMs: prefs[UserPreferences.mediaBarIntervalMs]
        )
        registerPreferenceObserver()
    }

    deinit {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
        preferencesChangeCancellable?.cancel()
        preferenceChangeTask?.cancel()
        preferenceReloadTask?.cancel()
    }

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    func load(userViews: [ServerItem] = []) async {
        lastUserViews = userViews

        guard isEnabled else {
            stopAutoAdvance()
            state = .disabled
            return
        }

        state = .loading
        do {
            let items = try await fetchItems()
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                state = .disabled
            } else {
                state = .ready(items)
                currentIndex = 0
                loadTime = Date()
                startAutoAdvance()
            }
        } catch {
            if !Task.isCancelled { state = .error(error.localizedDescription) }
        }
    }

    func goToNext() {
        guard case .ready(let items) = state, !items.isEmpty else { return }
        currentIndex = (currentIndex + 1) % items.count
        restartAutoAdvance()
    }

    func goToPrevious() {
        guard case .ready(let items) = state, !items.isEmpty else { return }
        currentIndex = (currentIndex - 1 + items.count) % items.count
        restartAutoAdvance()
    }

    func setFocused(_ focused: Bool) {
        isFocused = focused
        isPaused = focused
        if focused {
            stopAutoAdvance()
        } else {
            startAutoAdvance()
        }
    }

    func cleanup() {
        stopAutoAdvance()
    }

    func resume() {
        guard case .ready(let items) = state, items.count > 1 else { return }
        isPaused = false
        startAutoAdvance()
    }

    private func fetchItems() async throws -> [MediaBarSlideItem] {
        guard let client else { return [] }

        if container.pluginSyncService.isPluginAvailable,
           var serverItems = try? await fetchFromPlugin(client: client) {
            if !serverItems.isEmpty {
                let missingProviderIds = serverItems.contains { $0.providerIds == nil || $0.providerIds?.isEmpty == true }
                if missingProviderIds {
                    serverItems = await enrichWithProviderIds(items: serverItems, client: client)
                }
                return serverItems
            }
        }

        return try await fetchFromClient(client: client)
    }

    private func enrichWithProviderIds(items: [MediaBarSlideItem], client: MediaServerClient) async -> [MediaBarSlideItem] {
        let ids = items.filter { $0.providerIds == nil || $0.providerIds?.isEmpty == true }.map(\.id)
        guard !ids.isEmpty else { return items }

        let request = GetItemsRequest(
            fields: [.providerIds],
            ids: ids,
            enableImages: false,
            enableTotalRecordCount: false
        )
        guard let result = try? await client.itemsApi.getItems(request: request) else { return items }

        let providerMap: [String: [String: String]] = Dictionary(uniqueKeysWithValues: result.items.compactMap { item -> (String, [String: String])? in
            guard let pids = item.providerIds, !pids.isEmpty else { return nil }
            return (item.id, pids)
        })

        return items.map { item in
            if item.providerIds == nil || item.providerIds?.isEmpty == true,
               let pids = providerMap[item.id] {
                return MediaBarSlideItem(
                    id: item.id,
                    serverId: item.serverId,
                    title: item.title,
                    overview: item.overview,
                    backdropUrl: item.backdropUrl,
                    logoUrl: item.logoUrl,
                    year: item.year,
                    genres: item.genres,
                    runtime: item.runtime,
                    officialRating: item.officialRating,
                    communityRating: item.communityRating,
                    criticRating: item.criticRating,
                    itemType: item.itemType,
                    providerIds: pids
                )
            }
            return item
        }
    }

    private func fetchFromPlugin(client: MediaServerClient) async throws -> [MediaBarSlideItem] {
        let httpClient = client.httpClient

        struct MediaBarResponse: Decodable {
            let Items: [MediaBarItemDTO]
        }

        struct MediaBarItemDTO: Decodable {
            let Id: String
            let Name: String?
            let ItemType: String?
            let ProductionYear: Int?
            let OfficialRating: String?
            let RunTimeTicks: Int64?
            let Genres: [String]?
            let Overview: String?
            let CommunityRating: Double?
            let CriticRating: Double?
            let ImageTags: [String: String]?
            let BackdropImageTags: [String]?
            let ProviderIds: [String: String]?

            enum CodingKeys: String, CodingKey {
                case Id, Name, ProductionYear, OfficialRating, RunTimeTicks
                case Genres, Overview, CommunityRating, CriticRating
                case ImageTags, BackdropImageTags, ProviderIds
                case ItemType = "Type"
            }
        }

        let response: MediaBarResponse = try await httpClient.request(
            PluginSyncConstants.mediaBarPath,
            method: "GET",
            queryItems: [URLQueryItem(name: "profile", value: "tv")]
        )

        let imageApi = client.imageApi
        return response.Items.compactMap { dto in
            let backdropTag = dto.BackdropImageTags?.first
            guard backdropTag != nil else { return nil }

            let backdropUrl = imageApi.getItemImageUrl(
                itemId: dto.Id, imageType: .backdrop,
                maxWidth: 1920, maxHeight: nil, tag: backdropTag
            )
            let logoTag = dto.ImageTags?["Logo"]
            let logoUrl = logoTag.map {
                imageApi.getItemImageUrl(
                    itemId: dto.Id, imageType: .logo,
                    maxWidth: 400, maxHeight: nil, tag: $0
                )
            }

            var runtime: String?
            if let ticks = dto.RunTimeTicks, ticks > 0 {
                runtime = RuntimeFormatter.format(ticks: ticks)
            }

            let itemType = ItemType(rawValue: dto.ItemType ?? "") ?? .movie

            return MediaBarSlideItem(
                id: dto.Id,
                serverId: nil,
                title: dto.Name ?? "",
                overview: dto.Overview,
                backdropUrl: backdropUrl,
                logoUrl: logoUrl,
                year: dto.ProductionYear,
                genres: dto.Genres ?? [],
                runtime: runtime,
                officialRating: dto.OfficialRating,
                communityRating: dto.CommunityRating,
                criticRating: dto.CriticRating,
                itemType: itemType,
                providerIds: dto.ProviderIds
            )
        }
    }

    private func fetchFromClient(client: MediaServerClient) async throws -> [MediaBarSlideItem] {
        let prefs = container.userPreferences
        let contentType = prefs[UserPreferences.mediaBarContentType]
        let maxItems = prefs[UserPreferences.mediaBarItemCount].count
        let libraryIds = Self.normalizedIds(prefs[UserPreferences.mediaBarLibraryIds])
        let collectionIds = Self.normalizedIds(prefs[UserPreferences.mediaBarCollectionIds])
        let excludedGenres = Set(Self.normalizedGenres(prefs[UserPreferences.mediaBarExcludedGenres]))
        let scopedSourceIds: [String]
        if !libraryIds.isEmpty {
            scopedSourceIds = libraryIds
        } else if !collectionIds.isEmpty {
            scopedSourceIds = collectionIds
        } else {
            scopedSourceIds = []
        }
        let hasScopedSources = !scopedSourceIds.isEmpty

        var allItems: [ServerItem]

        let totalFetchBudget = max(maxItems * 2, 12)
        let perSourceFetchLimit = max(
            6,
            Int(ceil(Double(totalFetchBudget) / Double(max(scopedSourceIds.count, 1))))
        )

        if hasScopedSources {
            allItems = try await withThrowingTaskGroup(of: [ServerItem].self) { group in
                for sourceId in scopedSourceIds {
                    group.addTask {
                        try await self.fetchClientItems(
                            client: client,
                            contentType: contentType,
                            parentId: sourceId,
                            limit: perSourceFetchLimit
                        )
                    }
                }

                var collected: [ServerItem] = []
                for try await items in group {
                    collected.append(contentsOf: items)
                }
                return collected
            }

            if allItems.isEmpty {
                allItems = try await fetchClientItems(
                    client: client,
                    contentType: contentType,
                    parentId: nil,
                    limit: totalFetchBudget
                )
            }
        } else {
            allItems = try await fetchClientItems(
                client: client,
                contentType: contentType,
                parentId: nil,
                limit: totalFetchBudget
            )
        }

        let deduped = Self.dedupeItems(allItems)

        let filtered = container.parentalControlsRepository.filterItems(deduped)
            .filter { item in
                item.backdropImageTags?.isEmpty == false
                    || item.parentBackdropImageTags?.isEmpty == false
            }
            .filter { !Self.hasExcludedGenre(item: $0, excludedGenres: excludedGenres) }

        let shuffled = filtered.shuffled()
        let capped = Array(shuffled.prefix(maxItems))

        return capped.map { mapToSlideItem($0, client: client) }
    }

    private func fetchClientItems(
        client: MediaServerClient,
        contentType: MediaBarContentType,
        parentId: String?,
        limit: Int
    ) async throws -> [ServerItem] {
        let result = try await client.itemsApi.getItems(request: GetItemsRequest(
            parentId: parentId,
            recursive: true,
            includeItemTypes: contentType.itemTypes,
            excludeItemTypes: [.boxSet],
            sortBy: [.random],
            fields: Self.fetchFields,
            limit: limit,
            enableImages: true,
            imageTypeLimit: 1
        ))
        return result.items
    }

    private static func normalizedIds(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedGenres(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func hasExcludedGenre(item: ServerItem, excludedGenres: Set<String>) -> Bool {
        guard !excludedGenres.isEmpty, let itemGenres = item.genres else { return false }
        return itemGenres.contains { excludedGenres.contains($0.lowercased()) }
    }

    private static func dedupeItems(_ items: [ServerItem]) -> [ServerItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func registerPreferenceObserver() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePreferenceChange()
            }
        }

        preferencesChangeCancellable = container.userPreferences.objectWillChange
            .sink { [weak self] _ in
                self?.preferenceChangeTask?.cancel()
                self?.preferenceChangeTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    guard !Task.isCancelled else { return }
                    self?.handlePreferenceChange()
                }
            }
    }

    private func handlePreferenceChange() {
        let prefs = container.userPreferences
        let nextReloadSnapshot = ReloadPreferenceSnapshot(
            mode: prefs[UserPreferences.mediaBarMode],
            contentType: prefs[UserPreferences.mediaBarContentType],
            itemCount: prefs[UserPreferences.mediaBarItemCount],
            libraryIds: Self.normalizedIds(prefs[UserPreferences.mediaBarLibraryIds]),
            collectionIds: Self.normalizedIds(prefs[UserPreferences.mediaBarCollectionIds]),
            excludedGenres: Self.normalizedGenres(prefs[UserPreferences.mediaBarExcludedGenres])
        )
        let nextTimerSnapshot = TimerPreferenceSnapshot(
            autoAdvance: prefs[UserPreferences.mediaBarAutoAdvance],
            intervalMs: prefs[UserPreferences.mediaBarIntervalMs]
        )

        let reloadChanged = nextReloadSnapshot != reloadPreferenceSnapshot
        let timerChanged = nextTimerSnapshot != timerPreferenceSnapshot

        reloadPreferenceSnapshot = nextReloadSnapshot
        timerPreferenceSnapshot = nextTimerSnapshot

        if reloadChanged {
            preferenceReloadTask?.cancel()
            preferenceReloadTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.load(userViews: self.lastUserViews)
            }
            return
        }

        if timerChanged {
            restartAutoAdvance()
        }
    }

    private func mapToSlideItem(_ item: ServerItem, client: MediaServerClient) -> MediaBarSlideItem {
        let imageApi = client.imageApi

        var backdropUrl: String?
        if let tags = item.backdropImageTags, let tag = tags.first {
            backdropUrl = imageApi.getItemImageUrl(
                itemId: item.id, imageType: .backdrop,
                maxWidth: 1920, maxHeight: nil, tag: tag
            )
        } else if let parentTags = item.parentBackdropImageTags,
                  let parentId = item.parentBackdropItemId,
                  let tag = parentTags.first {
            backdropUrl = imageApi.getItemImageUrl(
                itemId: parentId, imageType: .backdrop,
                maxWidth: 1920, maxHeight: nil, tag: tag
            )
        }

        var logoUrl: String?
        if let logoTag = item.imageTags?["Logo"] {
            logoUrl = imageApi.getItemImageUrl(
                itemId: item.id, imageType: .logo,
                maxWidth: 400, maxHeight: nil, tag: logoTag
            )
        }

        var runtime: String?
        if let ticks = item.runTimeTicks, ticks > 0 {
            runtime = RuntimeFormatter.format(ticks: ticks)
        }

        return MediaBarSlideItem(
            id: item.id,
            serverId: item.serverId,
            title: item.name,
            overview: item.overview,
            backdropUrl: backdropUrl,
            logoUrl: logoUrl,
            year: item.productionYear,
            genres: item.genres ?? [],
            runtime: runtime,
            officialRating: item.officialRating,
            communityRating: item.communityRating,
            criticRating: item.criticRating,
            itemType: item.type,
            providerIds: item.providerIds
        )
    }

    private func startAutoAdvance() {
        guard container.userPreferences[UserPreferences.mediaBarAutoAdvance] else {
            stopAutoAdvance()
            return
        }
        guard !isPaused else { return }
        guard case .ready(let items) = state, items.count > 1 else { return }
        stopAutoAdvance()
        let intervalMs = max(1_000, container.userPreferences[UserPreferences.mediaBarIntervalMs])
        autoAdvanceTimer = Timer.publish(every: TimeInterval(intervalMs) / 1000, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.goToNext()
            }
    }

    private func stopAutoAdvance() {
        autoAdvanceTimer?.cancel()
        autoAdvanceTimer = nil
    }

    private func restartAutoAdvance() {
        stopAutoAdvance()
        startAutoAdvance()
    }
}
