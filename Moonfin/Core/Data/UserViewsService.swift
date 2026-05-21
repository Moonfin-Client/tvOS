import Foundation
import Combine

@MainActor
final class UserViewsService: ObservableObject {
    @Published private(set) var userViews: [ServerItem] = []

    private let serverRepository: ServerRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory
    private let userRepository: UserRepositoryProtocol
    private let userPreferences: UserPreferences
    private var unfilteredViews: [ServerItem] = []
    private var lastFolderViewEnabled: Bool?
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var currentContextKey: String?

    init(
        serverRepository: ServerRepositoryProtocol,
        serverClientFactory: MediaServerClientFactory,
        userRepository: UserRepositoryProtocol,
        userPreferences: UserPreferences
    ) {
        self.serverRepository = serverRepository
        self.serverClientFactory = serverClientFactory
        self.userRepository = userRepository
        self.userPreferences = userPreferences
        observeSessionContext()
        observePreferenceChanges()
    }

    private func observePreferenceChanges() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyFilterIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func applyFilterIfNeeded() {
        let showFolders = userPreferences[UserPreferences.enableFolderView]
        guard showFolders != lastFolderViewEnabled else { return }
        applyFilter(showFolders: showFolders)
    }

    private func applyFilter(showFolders: Bool? = nil) {
        let enabled = showFolders ?? userPreferences[UserPreferences.enableFolderView]
        lastFolderViewEnabled = enabled
        userViews = unfilteredViews.filter { item in
            if item.collectionType?.lowercased() == "folders" {
                return enabled
            }
            return true
        }
    }

    private func observeSessionContext() {
        userRepository.currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshViewsForCurrentContext()
            }
            .store(in: &cancellables)

        serverRepository.currentServer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshViewsForCurrentContext()
            }
            .store(in: &cancellables)
    }

    private func refreshViewsForCurrentContext() {
        guard let user = userRepository.currentUser.value,
              let server = serverRepository.currentServer.value else {
            loadTask?.cancel()
            loadTask = nil
            currentContextKey = nil
            if !unfilteredViews.isEmpty {
                unfilteredViews = []
                userViews = []
            }
            return
        }

        let contextKey = "\(server.id.uuidString)|\(user.id)"
        guard contextKey != currentContextKey else { return }

        currentContextKey = contextKey
        fetchViews(userId: user.id, server: server, contextKey: contextKey)
    }

    private func fetchViews(userId: String, server: Server, contextKey: String) {
        loadTask?.cancel()
        loadTask = Task {
            let client = serverClientFactory.client(for: server)
            do {
                let views = try await client.userViewsApi.getUserViews(userId: userId)
                guard !Task.isCancelled else { return }
                guard self.currentContextKey == contextKey else { return }
                self.unfilteredViews = views
                self.applyFilter()
            } catch {
                guard !Task.isCancelled else { return }
                guard self.currentContextKey == contextKey else { return }
                self.currentContextKey = nil
                self.unfilteredViews = []
                self.userViews = []
            }
        }
    }

    func awaitLoaded() async -> [ServerItem] {
        if let loadTask {
            await loadTask.value
        }
        return userViews
    }
}

struct HomeScreenSectionsCapability: Equatable {
    let serverId: UUID
    let serverName: String
    let installed: Bool
    let enabled: Bool
    let pluginVersion: String?
    let sections: [HomeScreenSectionInfo]
    let lastErrorDescription: String?
    let lastUpdatedAt: Date

    var isAvailable: Bool {
        installed && enabled
    }
}

@MainActor
final class HomeScreenSectionsService: ObservableObject {
    @Published private(set) var activeCapability: HomeScreenSectionsCapability?
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshCompletedCount = 0

    private let serverRepository: ServerRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory
    private let userPreferences: UserPreferences

    private var capabilitiesByServerId: [UUID: HomeScreenSectionsCapability] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?

    private static let homeScreenSectionsPluginGuid = "b8298e01-2697-407a-b44d-aa8dc795e850"

    init(
        serverRepository: ServerRepositoryProtocol,
        serverClientFactory: MediaServerClientFactory,
        userPreferences: UserPreferences
    ) {
        self.serverRepository = serverRepository
        self.serverClientFactory = serverClientFactory
        self.userPreferences = userPreferences
        observeSessionContext()
        requestRefresh()
    }

    deinit {
        refreshTask?.cancel()
    }

    func requestRefresh(shouldMergeDiscoveredSections: Bool = true) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshActiveServerNow(shouldMergeDiscoveredSections: shouldMergeDiscoveredSections)
        }
    }

    func refreshActiveServerNow(shouldMergeDiscoveredSections: Bool = true) async {
        guard let server = serverRepository.currentServer.value else {
            activeCapability = nil
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let client = serverClientFactory.client(for: server)
        let capability = await probeCapability(server: server, client: client)
        guard !Task.isCancelled else { return }

        capabilitiesByServerId[server.id] = capability
        activeCapability = capability

        if shouldMergeDiscoveredSections, capability.isAvailable {
            mergeDiscoveredSections(capability.sections, for: server, source: .hss)
        }

        refreshCompletedCount += 1
    }

    private func observeSessionContext() {
        serverRepository.currentServer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] server in
                guard let self else { return }
                if let server {
                    activeCapability = capabilitiesByServerId[server.id]
                } else {
                    activeCapability = nil
                }
                requestRefresh()
            }
            .store(in: &cancellables)

        serverRepository.storedServers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] servers in
                self?.handleStoredServersChanged(servers)
            }
            .store(in: &cancellables)
    }

    private func handleStoredServersChanged(_ servers: [Server]) {
        let validServerIds = Set(servers.map(\.id))
        capabilitiesByServerId = capabilitiesByServerId.filter { validServerIds.contains($0.key) }

        var validServerIdentifiers = Set<String>()
        for server in servers {
            validServerIdentifiers.insert(normalizedServerIdentifier(server.id.uuidString))
            validServerIdentifiers.insert(normalizedServerIdentifier(server.address))
        }

        pruneOrphanedPluginConfigs(validServerIdentifiers: validServerIdentifiers)

        if let current = serverRepository.currentServer.value {
            activeCapability = capabilitiesByServerId[current.id]
        } else {
            activeCapability = nil
        }
    }

    private func probeCapability(server: Server, client: MediaServerClient) async -> HomeScreenSectionsCapability {
        guard let api = client.homeScreenSectionsApi else {
            return HomeScreenSectionsCapability(
                serverId: server.id,
                serverName: server.name,
                installed: false,
                enabled: false,
                pluginVersion: nil,
                sections: [],
                lastErrorDescription: nil,
                lastUpdatedAt: Date()
            )
        }

        var installedVersion: String?
        var adminProbeError: Error?

        if let adminApi = client.adminPluginsApi {
            do {
                let plugins = try await adminApi.getInstalledPlugins()
                installedVersion = plugins.first {
                    $0.id.lowercased() == Self.homeScreenSectionsPluginGuid
                }?.version
            } catch {
                if !isIgnorableAdminProbeError(error) {
                    adminProbeError = error
                }
            }
        }

        var meta: HomeScreenMeta?
        var metaError: Error?
        do {
            meta = try await api.getMeta()
        } catch {
            metaError = error
        }

        if installedVersion == nil && isNotInstalledResponse(metaError) {
            metaError = nil
        }

        let installed = installedVersion != nil || meta != nil
        let enabled = meta?.enabled ?? false

        var sections: [HomeScreenSectionInfo] = []
        var sectionsError: Error?

        if installed && enabled {
            do {
                sections = try await api.getUserSections()
            } catch {
                sectionsError = error
            }
        }

        let chosenError = sectionsError ?? metaError ?? adminProbeError

        return HomeScreenSectionsCapability(
            serverId: server.id,
            serverName: server.name,
            installed: installed,
            enabled: enabled,
            pluginVersion: installedVersion,
            sections: sections,
            lastErrorDescription: chosenError?.localizedDescription,
            lastUpdatedAt: Date()
        )
    }

    private func isIgnorableAdminProbeError(_ error: Error) -> Bool {
        guard let code = statusCode(from: error) else { return false }
        return code == 401 || code == 403 || code == 404
    }

    private func isNotInstalledResponse(_ error: Error?) -> Bool {
        guard let error, let code = statusCode(from: error) else { return false }
        return code == 404
    }

    private func statusCode(from error: Error) -> Int? {
        guard let networkError = error as? NetworkError else { return nil }
        if case .httpError(let statusCode, _) = networkError {
            return statusCode
        }
        return nil
    }

    private func mergeDiscoveredSections(
        _ discoveredSections: [HomeScreenSectionInfo],
        for server: Server,
        source: HomeSectionPluginSource
    ) {
        let existing = userPreferences.homeSectionsConfig
        let serverIdentifier = normalizedServerIdentifier(server.id.uuidString)

        func isTarget(_ config: HomeSectionConfig) -> Bool {
            guard config.isPluginDynamic, config.pluginSource == source else { return false }
            return normalizedOptionalServerIdentifier(config.serverId) == serverIdentifier
        }

        let targetExistingByStableId = Dictionary(
            uniqueKeysWithValues: existing
                .filter(isTarget)
                .map { ($0.stableId, $0) }
        )

        var discoveredByStableId: [String: HomeSectionConfig] = [:]

        for info in discoveredSections {
            let section = info.section.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !section.isEmpty else { continue }

            let additionalData = normalizedOptionalValue(info.additionalData)
            let displayText = normalizedOptionalValue(info.displayText) ?? section

            var discovered = HomeSectionConfig.pluginDynamic(
                enabled: false,
                order: 0,
                serverId: server.id.uuidString,
                pluginSection: section,
                pluginAdditionalData: additionalData,
                pluginDisplayText: displayText,
                pluginSource: source
            )

            if let existingConfig = targetExistingByStableId[discovered.stableId] {
                discovered = existingConfig
                discovered.serverId = server.id.uuidString
                discovered.pluginSection = section
                discovered.pluginAdditionalData = additionalData
                discovered.pluginDisplayText = displayText
                discovered.pluginSource = source
            }

            discoveredByStableId[discovered.stableId] = discovered
        }

        let sortedExisting = existing.sorted { $0.order < $1.order }
        var merged: [HomeSectionConfig] = []
        var consumedStableIds = Set<String>()

        for config in sortedExisting {
            if isTarget(config) {
                if var replacement = discoveredByStableId[config.stableId],
                   !consumedStableIds.contains(config.stableId) {
                    replacement.order = merged.count
                    merged.append(replacement)
                    consumedStableIds.insert(config.stableId)
                }
                continue
            }

            var preserved = config
            preserved.order = merged.count
            merged.append(preserved)
        }

        let remainingDiscovered = discoveredByStableId.values
            .filter { !consumedStableIds.contains($0.stableId) }
            .sorted { lhs, rhs in
                let lhsName = lhs.pluginDisplayText ?? lhs.pluginSection ?? lhs.stableId
                let rhsName = rhs.pluginDisplayText ?? rhs.pluginSection ?? rhs.stableId
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

        for var config in remainingDiscovered {
            config.order = merged.count
            merged.append(config)
        }

        let normalizedMerged = HomeSectionConfig.normalized(merged)
        let oldStorage = HomeSectionConfig.toStorageString(existing)
        let newStorage = HomeSectionConfig.toStorageString(normalizedMerged)
        if oldStorage != newStorage {
            userPreferences.setHomeSectionsConfig(normalizedMerged)
        }
    }

    private func pruneOrphanedPluginConfigs(validServerIdentifiers: Set<String>) {
        let existing = userPreferences.homeSectionsConfig
        let filtered = existing.filter { config in
            guard config.isPluginDynamic else { return true }
            guard let serverId = normalizedOptionalServerIdentifier(config.serverId) else { return true }
            return validServerIdentifiers.contains(serverId)
        }

        guard filtered.count != existing.count else { return }
        userPreferences.setHomeSectionsConfig(HomeSectionConfig.normalized(filtered))
    }

    private func normalizedServerIdentifier(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private func normalizedOptionalValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func normalizedOptionalServerIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalizedServerIdentifier(value)
        return normalized.isEmpty ? nil : normalized
    }
}

@MainActor
final class HomePluginSectionsService: ObservableObject {
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshCompletedCount = 0

    private let serverRepository: ServerRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory
    private let userPreferences: UserPreferences

    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?

    private var lastCollectionsEnabled: Bool
    private var lastGenresEnabled: Bool
    private var lastGenresItems: GenresRowItems

    private static let pageSize = 250
    private static let maxGenreDiscoveryPages = 40

    init(
        serverRepository: ServerRepositoryProtocol,
        serverClientFactory: MediaServerClientFactory,
        userPreferences: UserPreferences
    ) {
        self.serverRepository = serverRepository
        self.serverClientFactory = serverClientFactory
        self.userPreferences = userPreferences
        self.lastCollectionsEnabled = userPreferences[UserPreferences.displayCollectionsRows]
        self.lastGenresEnabled = userPreferences[UserPreferences.displayGenresRows]
        self.lastGenresItems = userPreferences[UserPreferences.genresRowItems]

        observeSessionContext()
        observePreferenceChanges()
        requestRefresh()
    }

    deinit {
        refreshTask?.cancel()
    }

    func requestRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshActiveServerNow()
        }
    }

    func refreshActiveServerNow() async {
        guard let server = serverRepository.currentServer.value else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let client = serverClientFactory.client(for: server)

        await refreshCollections(for: server, client: client)
        await refreshGenres(for: server, client: client)
        await refreshKefinTweaks(for: server, client: client)

        guard !Task.isCancelled else { return }
        refreshCompletedCount += 1
    }

    private func observeSessionContext() {
        serverRepository.currentServer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestRefresh()
            }
            .store(in: &cancellables)

        serverRepository.storedServers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] servers in
                self?.handleStoredServersChanged(servers)
            }
            .store(in: &cancellables)
    }

    private func observePreferenceChanges() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePreferenceChangeIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func handlePreferenceChangeIfNeeded() {
        let collectionsEnabled = userPreferences[UserPreferences.displayCollectionsRows]
        let genresEnabled = userPreferences[UserPreferences.displayGenresRows]
        let genresItems = userPreferences[UserPreferences.genresRowItems]

        let changed = collectionsEnabled != lastCollectionsEnabled
            || genresEnabled != lastGenresEnabled
            || genresItems != lastGenresItems

        lastCollectionsEnabled = collectionsEnabled
        lastGenresEnabled = genresEnabled
        lastGenresItems = genresItems

        guard changed else { return }
        requestRefresh()
    }

    private func handleStoredServersChanged(_ servers: [Server]) {
        var validServerIdentifiers = Set<String>()
        for server in servers {
            validServerIdentifiers.insert(normalizedServerIdentifier(server.id.uuidString))
            validServerIdentifiers.insert(normalizedServerIdentifier(server.address))
        }

        pruneOrphanedPluginConfigs(validServerIdentifiers: validServerIdentifiers)
    }

    private func refreshCollections(for server: Server, client: MediaServerClient) async {
        guard userPreferences[UserPreferences.displayCollectionsRows] else {
            mergeDiscoveredSections([], for: server, source: .collections)
            return
        }

        do {
            var discovered: [HomeScreenSectionInfo] = []
            var startIndex = 0

            while true {
                let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.boxSet],
                    sortBy: [.sortName],
                    sortOrder: .ascending,
                    fields: [.childCount],
                    limit: Self.pageSize,
                    startIndex: startIndex,
                    enableTotalRecordCount: true
                ))

                guard !Task.isCancelled else { return }

                for item in result.items {
                    let displayText = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let additionalData = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !displayText.isEmpty, !additionalData.isEmpty else { continue }
                    discovered.append(HomeScreenSectionInfo(
                        section: "collection",
                        displayText: displayText,
                        additionalData: additionalData
                    ))
                }

                startIndex += result.items.count
                if result.items.isEmpty || startIndex >= result.totalRecordCount {
                    break
                }
            }

            mergeDiscoveredSections(discovered, for: server, source: .collections)
        } catch {
            guard !Task.isCancelled else { return }
        }
    }

    private func refreshGenres(for server: Server, client: MediaServerClient) async {
        guard userPreferences[UserPreferences.displayGenresRows] else {
            mergeDiscoveredSections([], for: server, source: .genres)
            return
        }

        do {
            var discoveredOrder: [String] = []
            var seenGenres = Set<String>()
            var startIndex = 0
            var pages = 0

            while pages < Self.maxGenreDiscoveryPages {
                let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                    recursive: true,
                    includeItemTypes: genresIncludeItemTypes(),
                    excludeItemTypes: [.episode],
                    sortBy: [.sortName],
                    sortOrder: .ascending,
                    fields: [.genres],
                    limit: Self.pageSize,
                    startIndex: startIndex,
                    enableTotalRecordCount: true
                ))

                guard !Task.isCancelled else { return }

                for item in result.items {
                    for genre in item.genres ?? [] {
                        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        let key = trimmed.lowercased()
                        if seenGenres.insert(key).inserted {
                            discoveredOrder.append(trimmed)
                        }
                    }
                }

                startIndex += result.items.count
                pages += 1
                if result.items.isEmpty || startIndex >= result.totalRecordCount {
                    break
                }
            }

            let discovered = discoveredOrder.map { genre in
                HomeScreenSectionInfo(section: "genre", displayText: genre, additionalData: genre)
            }
            mergeDiscoveredSections(discovered, for: server, source: .genres)
        } catch {
            guard !Task.isCancelled else { return }
        }
    }

    private func refreshKefinTweaks(for server: Server, client: MediaServerClient) async {
        guard let api = client.kefinTweaksApi else {
            mergeDiscoveredSections([], for: server, source: .kefinTweaks)
            return
        }

        do {
            guard let config = try await api.fetchConfig() else {
                mergeDiscoveredSections([], for: server, source: .kefinTweaks)
                return
            }

            guard config.homeScreen.enabled else {
                mergeDiscoveredSections([], for: server, source: .kefinTweaks)
                return
            }

            let discovered = buildKefinDiscoveredSections(config)
            mergeDiscoveredSections(discovered, for: server, source: .kefinTweaks)
        } catch {
            guard !Task.isCancelled else { return }
        }
    }

    private func buildKefinDiscoveredSections(_ config: KefinTweaksConfig) -> [HomeScreenSectionInfo] {
        struct Entry {
            let id: String
            let displayText: String
            let order: Int
            let spec: [String: Any]
        }

        let home = config.homeScreen
        let defaultLimit = home.defaultItemLimit
        var entries: [Entry] = []

        let released = home.recentlyReleased
        let releasedMovies = released?.movies
        if released?.enabled != false, releasedMovies?.enabled != false {
            entries.append(Entry(
                id: "recentlyReleasedMovies",
                displayText: releasedMovies?.name ?? "Recently Released Movies",
                order: releasedMovies?.order ?? 21,
                spec: [
                    "kind": "recentlyReleasedMovies",
                    "limit": releasedMovies?.itemLimit ?? defaultLimit,
                ]
            ))
        }

        let releasedEpisodes = released?.episodes
        if released?.enabled != false, releasedEpisodes?.enabled != false {
            entries.append(Entry(
                id: "recentlyReleasedEpisodes",
                displayText: releasedEpisodes?.name ?? "Recently Released Episodes",
                order: releasedEpisodes?.order ?? 22,
                spec: [
                    "kind": "recentlyReleasedEpisodes",
                    "limit": releasedEpisodes?.itemLimit ?? defaultLimit,
                ]
            ))
        }

        let watchAgain = home.watchAgain
        if watchAgain?.enabled != false {
            entries.append(Entry(
                id: "watchAgain",
                displayText: watchAgain?.name ?? "Watch Again",
                order: watchAgain?.order ?? 50,
                spec: [
                    "kind": "watchAgain",
                    "limit": watchAgain?.itemLimit ?? defaultLimit,
                ]
            ))
        }

        if let recentlyAddedInLibrary = home.recentlyAddedInLibrary {
            var libraryIds: [String] = []

            for (libraryId, value) in recentlyAddedInLibrary {
                if let valueObject = value as? [String: Any] {
                    let enabled = (valueObject["enabled"] as? Bool) ?? true
                    if enabled {
                        libraryIds.append(libraryId)
                    }
                } else {
                    libraryIds.append(libraryId)
                }
            }

            if !libraryIds.isEmpty {
                entries.append(Entry(
                    id: "recentlyAddedInLibrary",
                    displayText: "Recently Added",
                    order: 90,
                    spec: [
                        "kind": "recentlyAddedInLibrary",
                        "libraryIds": libraryIds,
                        "limit": defaultLimit,
                    ]
                ))
            }
        }

        if let seasonal = home.seasonal {
            let now = Date()

            for (key, rawValue) in seasonal {
                guard let value = rawValue as? [String: Any] else { continue }
                if let enabled = value["enabled"] as? Bool, !enabled { continue }

                let startDate = (value["startDate"] as? String) ?? ""
                let endDate = (value["endDate"] as? String) ?? ""
                guard seasonalWindowIsActive(now: now, startMmDd: startDate, endMmDd: endDate) else { continue }

                let itemTypes = stringList(from: value["includeItemTypes"]) ?? ["Movie"]
                let sectionLimit = (value["itemLimit"] as? NSNumber)?.intValue ?? defaultLimit
                let order = (value["order"] as? NSNumber)?.intValue ?? 60
                let displayText = (value["name"] as? String) ?? key

                entries.append(Entry(
                    id: "seasonal:\(key)",
                    displayText: displayText,
                    order: order,
                    spec: [
                        "kind": "custom",
                        "type": (value["type"] as? String) ?? "genre",
                        "source": (value["source"] as? String) ?? "",
                        "sortBy": (value["sortOrder"] as? String) ?? "Random",
                        "sortOrderDirection": (value["sortOrderDirection"] as? String) ?? "Ascending",
                        "includeItemTypes": itemTypes,
                        "limit": sectionLimit,
                    ]
                ))
            }
        }

        if let customSections = home.customSections {
            for (index, rawEntry) in customSections.enumerated() {
                guard let entry = rawEntry as? [String: Any] else { continue }
                if let enabled = entry["enabled"] as? Bool, !enabled { continue }

                let type = (entry["type"] as? String) ?? "genre"
                let source = (entry["source"] as? String) ?? ""
                let itemTypes = stringList(from: entry["includeItemTypes"]) ?? ["Movie", "Series"]
                let sectionLimit = (entry["limit"] as? NSNumber)?.intValue
                    ?? (entry["itemLimit"] as? NSNumber)?.intValue
                    ?? defaultLimit
                let order = (entry["order"] as? NSNumber)?.intValue ?? (100 + index)
                let displayText = (entry["name"] as? String) ?? "Custom"

                let explicitId = (entry["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackId = "\(type):\(source):\(index)"
                let sectionId = !((explicitId ?? "").isEmpty) ? (explicitId ?? fallbackId) : fallbackId

                entries.append(Entry(
                    id: "custom:\(sectionId)",
                    displayText: displayText,
                    order: order,
                    spec: [
                        "kind": "custom",
                        "type": type,
                        "source": source,
                        "sortBy": (entry["sortOrder"] as? String) ?? "Random",
                        "sortOrderDirection": (entry["sortOrderDirection"] as? String) ?? "Ascending",
                        "includeItemTypes": itemTypes,
                        "limit": sectionLimit,
                    ]
                ))
            }
        }

        return entries
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
                }
                return lhs.order < rhs.order
            }
            .compactMap { entry in
                guard JSONSerialization.isValidJSONObject(entry.spec),
                      let data = try? JSONSerialization.data(withJSONObject: entry.spec),
                      let json = String(data: data, encoding: .utf8)
                else {
                    return nil
                }

                return HomeScreenSectionInfo(
                    section: "kefin:\(entry.id)",
                    displayText: entry.displayText,
                    additionalData: json
                )
            }
    }

    private func seasonalWindowIsActive(now: Date, startMmDd: String, endMmDd: String) -> Bool {
        guard let start = parseMmDd(startMmDd),
              let end = parseMmDd(endMmDd) else {
            return false
        }

        let calendar = Calendar.current
        let today = (calendar.component(.month, from: now), calendar.component(.day, from: now))

        func compare(_ lhs: (Int, Int), _ rhs: (Int, Int)) -> Int {
            if lhs.0 != rhs.0 {
                return lhs.0 < rhs.0 ? -1 : 1
            }
            if lhs.1 == rhs.1 {
                return 0
            }
            return lhs.1 < rhs.1 ? -1 : 1
        }

        if compare(start, end) <= 0 {
            return compare(today, start) >= 0 && compare(today, end) <= 0
        }

        return compare(today, start) >= 0 || compare(today, end) <= 0
    }

    private func parseMmDd(_ value: String) -> (Int, Int)? {
        let parts = value.split(separator: "-")
        guard parts.count >= 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]) else {
            return nil
        }
        return (month, day)
    }

    private func stringList(from value: Any?) -> [String]? {
        guard let values = value as? [Any] else { return nil }
        let strings = values
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return strings.isEmpty ? nil : strings
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

    private func mergeDiscoveredSections(
        _ discoveredSections: [HomeScreenSectionInfo],
        for server: Server,
        source: HomeSectionPluginSource
    ) {
        let existing = userPreferences.homeSectionsConfig
        let serverIdentifier = normalizedServerIdentifier(server.id.uuidString)

        func isTarget(_ config: HomeSectionConfig) -> Bool {
            guard config.isPluginDynamic, config.pluginSource == source else { return false }
            return normalizedOptionalServerIdentifier(config.serverId) == serverIdentifier
        }

        let targetExistingByStableId = Dictionary(
            uniqueKeysWithValues: existing
                .filter(isTarget)
                .map { ($0.stableId, $0) }
        )

        var discoveredByStableId: [String: HomeSectionConfig] = [:]

        for info in discoveredSections {
            let section = info.section.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !section.isEmpty else { continue }

            let additionalData = normalizedOptionalValue(info.additionalData)
            let displayText = normalizedOptionalValue(info.displayText) ?? section

            var discovered = HomeSectionConfig.pluginDynamic(
                enabled: false,
                order: 0,
                serverId: server.id.uuidString,
                pluginSection: section,
                pluginAdditionalData: additionalData,
                pluginDisplayText: displayText,
                pluginSource: source
            )

            if let existingConfig = targetExistingByStableId[discovered.stableId] {
                discovered = existingConfig
                discovered.serverId = server.id.uuidString
                discovered.pluginSection = section
                discovered.pluginAdditionalData = additionalData
                discovered.pluginDisplayText = displayText
                discovered.pluginSource = source
            }

            discoveredByStableId[discovered.stableId] = discovered
        }

        let sortedExisting = existing.sorted { $0.order < $1.order }
        var merged: [HomeSectionConfig] = []
        var consumedStableIds = Set<String>()

        for config in sortedExisting {
            if isTarget(config) {
                if var replacement = discoveredByStableId[config.stableId],
                   !consumedStableIds.contains(config.stableId) {
                    replacement.order = merged.count
                    merged.append(replacement)
                    consumedStableIds.insert(config.stableId)
                }
                continue
            }

            var preserved = config
            preserved.order = merged.count
            merged.append(preserved)
        }

        let remainingDiscovered = discoveredByStableId.values
            .filter { !consumedStableIds.contains($0.stableId) }
            .sorted { lhs, rhs in
                let lhsName = lhs.pluginDisplayText ?? lhs.pluginSection ?? lhs.stableId
                let rhsName = rhs.pluginDisplayText ?? rhs.pluginSection ?? rhs.stableId
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

        for var config in remainingDiscovered {
            config.order = merged.count
            merged.append(config)
        }

        let normalizedMerged = HomeSectionConfig.normalized(merged)
        let oldStorage = HomeSectionConfig.toStorageString(existing)
        let newStorage = HomeSectionConfig.toStorageString(normalizedMerged)
        if oldStorage != newStorage {
            userPreferences.setHomeSectionsConfig(normalizedMerged)
        }
    }

    private func pruneOrphanedPluginConfigs(validServerIdentifiers: Set<String>) {
        let existing = userPreferences.homeSectionsConfig
        let filtered = existing.filter { config in
            guard config.isPluginDynamic else { return true }
            guard let serverId = normalizedOptionalServerIdentifier(config.serverId) else { return true }
            return validServerIdentifiers.contains(serverId)
        }

        guard filtered.count != existing.count else { return }
        userPreferences.setHomeSectionsConfig(HomeSectionConfig.normalized(filtered))
    }

    private func normalizedServerIdentifier(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private func normalizedOptionalValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func normalizedOptionalServerIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalizedServerIdentifier(value)
        return normalized.isEmpty ? nil : normalized
    }
}
