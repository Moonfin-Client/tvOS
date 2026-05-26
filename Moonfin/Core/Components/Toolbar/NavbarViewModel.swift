import SwiftUI
import Combine

struct AccountSwitcherAccount: Identifiable, Equatable {
    let server: Server
    let user: PrivateUser
    let imageUrl: String?
    let isActive: Bool

    var id: String {
        "\(server.id.uuidString)-\(user.id.uuidString)"
    }
}

@MainActor
final class NavbarViewModel: ObservableObject {
    @Published var userImageUrl: String?
    @Published var userName: String = ""
    @Published var userViews: [ServerItem] = []

    @Published var showShuffle: Bool = true
    @Published var showGenres: Bool = true
    @Published var showFavorites: Bool = true
    @Published var showLibraries: Bool = true
    @Published var showSyncPlay: Bool = false
    @Published var showSeerrInNavigation: Bool = false
    @Published var showSeerrInToolbar: Bool = false
    @Published var seerrDisplayName: String = "Seerr"
    @Published var seerrIconName: String = "seerr"

    @Published var overlayColor: Color = MediaBarOverlayColor.gray.color
    @Published var overlayOpacity: Double = 0.5

    private let container: AppContainer
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainer) {
        self.container = container
        refreshPreferences()
        observeUser()
        observePreferenceChanges()
        observeSeerrAvailability()
    }

    private func observeUser() {
        container.userRepository.currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self else { return }
                if let user {
                    self.userName = user.name
                    self.loadUserImage(user: user)
                } else {
                    self.userName = ""
                    self.userImageUrl = nil
                }
            }
            .store(in: &cancellables)

        container.userViewsService.$userViews
            .receive(on: DispatchQueue.main)
            .assign(to: &$userViews)
    }

    private func observePreferenceChanges() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPreferences()
            }
            .store(in: &cancellables)

        container.pluginSyncService.$syncCompletedCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPreferences()
            }
            .store(in: &cancellables)
    }

    private func observeSeerrAvailability() {
        container.seerrRepository.isAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSeerrVisibility()
            }
            .store(in: &cancellables)
    }

    private func refreshPreferences() {
        let prefs = container.userPreferences
        showShuffle = prefs[UserPreferences.showShuffleButton]
        showGenres = prefs[UserPreferences.showGenresButton]
        showFavorites = prefs[UserPreferences.showFavoritesButton]
        showLibraries = prefs[UserPreferences.showLibrariesInToolbar]
        showSyncPlay = {
            guard prefs[UserPreferences.syncPlayEnabled],
                  let client = self.client else { return false }
            return client.serverType.supports(.syncPlay)
        }()
        overlayColor = prefs[UserPreferences.navbarColor].color
        overlayOpacity = Double(prefs[UserPreferences.navbarOpacity]) / 100.0
        refreshSeerrVisibility()
    }

    private func refreshSeerrVisibility() {
        let available = container.seerrRepository.isAvailable.value
        if let seerrPrefs = container.seerrRepository.getPreferences() {
            let enabled = seerrPrefs[SeerrPreferences.enabled] || available
            let authenticated = isSeerrAuthenticated(seerrPrefs, available: available)
            let showInNavigationPref = seerrPrefs[SeerrPreferences.showInNavigation]
            let showInToolbarPref = seerrPrefs[SeerrPreferences.showInToolbar]
            let nextShowInNavigation = enabled && available && authenticated && showInNavigationPref
            let nextShowInToolbar = enabled && available && authenticated && showInToolbarPref

            let variant = SeerrPreferences.normalizeVariant(seerrPrefs[SeerrPreferences.moonfinVariant])
            let dn = seerrPrefs[SeerrPreferences.moonfinDisplayName]
            let nextDisplayName = dn.isEmpty ? (variant == "seerr" ? "Seerr" : "Jellyseerr") : dn
            let nextIconName = variant == "seerr" ? "seerr" : "jellyseerr"

            if showSeerrInNavigation != nextShowInNavigation {
                showSeerrInNavigation = nextShowInNavigation
            }
            if showSeerrInToolbar != nextShowInToolbar {
                showSeerrInToolbar = nextShowInToolbar
            }
            if seerrDisplayName != nextDisplayName {
                seerrDisplayName = nextDisplayName
            }
            if seerrIconName != nextIconName {
                seerrIconName = nextIconName
            }
        } else {
            if showSeerrInNavigation {
                showSeerrInNavigation = false
            }
            if showSeerrInToolbar {
                showSeerrInToolbar = false
            }
            if seerrDisplayName != "Seerr" {
                seerrDisplayName = "Seerr"
            }
            if seerrIconName != "seerr" {
                seerrIconName = "seerr"
            }
        }
    }

    private func isSeerrAuthenticated(_ prefs: SeerrPreferences, available: Bool) -> Bool {
        let authMethod = prefs[SeerrPreferences.authMethod]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if prefs[SeerrPreferences.moonfinMode] || authMethod == "moonfin" {
            return true
        }

        guard !authMethod.isEmpty else { return false }

        if authMethod.contains("apikey") {
            return !prefs[SeerrPreferences.apiKey]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }

        if authMethod == "jellyfin" || authMethod == "local" {
            return prefs[SeerrPreferences.lastConnectionSuccess] || available
        }

        return available
    }

    private func loadUserImage(user: ServerUser) {
        guard let server = container.serverRepository.currentServer.value,
              let tag = user.primaryImageTag else {
            userImageUrl = nil
            return
        }
        let client = container.serverClientFactory.client(for: server)
        userImageUrl = client.imageApi.getUserImageUrl(
            userId: user.id, imageType: .primary, tag: tag
        )
    }

    var currentServerId: UUID? {
        container.serverRepository.currentServer.value?.id
    }

    func accountSwitcherAccounts() -> [AccountSwitcherAccount] {
        container.serverRepository.loadStoredServers()
        let currentSession = container.sessionRepository.currentSession.value

        return container.serverRepository.storedServers.value.flatMap { server in
            container.serverUserRepository
                .getStoredServerUsers(server: server)
                .filter { user in
                    guard let token = user.accessToken else { return false }
                    return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .map { user in
                    AccountSwitcherAccount(
                        server: server,
                        user: user,
                        imageUrl: container.authenticationRepository.getUserImageUrl(server: server, user: user),
                        isActive: currentSession?.serverId == server.id && currentSession?.userId == user.id
                    )
                }
        }
    }

    func addScreensaverLock() {
        container.inactivityTracker.addLock()
    }

    func removeScreensaverLock() {
        container.inactivityTracker.removeLock()
    }

    func signOutCurrentSession() {
        container.sessionRepository.destroyCurrentSession()
    }

    func signOutAllStoredAccounts() {
        container.sessionRepository.destroyCurrentSession()
        container.serverRepository.loadStoredServers()
        for server in container.serverRepository.storedServers.value {
            _ = container.serverRepository.deleteServer(id: server.id)
        }
    }

    @Published var isShuffling = false

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    func performShuffle(libraryId: String? = nil, genreName: String? = nil, router: NavigationRouter) {
        let contentType = shuffleContentType
        let selectedLibraryId = normalizedShuffleLibraryId(libraryId, contentType: contentType)
        Task {
            guard let item = await shuffle(contentType: contentType, libraryId: selectedLibraryId, genreName: genreName) else { return }
            router.navigatePrimaryToItem(item)
        }
    }

    var shuffleLibraries: [ServerItem] {
        let contentType = shuffleContentType
        return userViews.filter { isEligibleShuffleLibrary($0, contentType: contentType) }
    }

    private var shuffleContentType: ShuffleContentType {
        container.userPreferences[UserPreferences.shuffleContentType]
    }

    var enableAdditionalRatings: Bool {
        container.userPreferences[UserPreferences.enableAdditionalRatings]
    }

    func fetchShuffleRatings(for item: ServerItem) async -> [(String, Float)] {
        var result: [(String, Float)] = []
        let enabledSourcesOrdered = RatingSource.canonicalEnabledSourceOrder(container.userPreferences[UserPreferences.enabledRatings])
        let episodeRatingsEnabled = container.userPreferences[UserPreferences.enableEpisodeRatings]

        func appendUnique(_ source: String, _ value: Float) {
            let canonical = RatingSource.canonicalSourceRawValue(source)
            guard !canonical.isEmpty else { return }
            if !result.contains(where: { $0.0 == canonical }) {
                result.append((canonical, value))
            }
        }

        if let community = item.communityRating, community > 0 {
            appendUnique(RatingSource.communityRawValue, Float(community))
        }

        if enableAdditionalRatings,
           let apiRatings = await container.mdbListRepository.getRatings(item: item) {
            for (source, value) in apiRatings {
                let canonical = RatingSource.canonicalSourceRawValue(source)
                if canonical == "tomatoes" && item.criticRating != nil { continue }
                if let normalized = RatingSource.normalizedApiRating(source: canonical, rawValue: value) {
                    appendUnique(normalized.source, normalized.normalizedValue)
                }
            }
        }

        if let critic = item.criticRating, critic > 0 {
            appendUnique("tomatoes", RatingSource.tomatoes.normalize(Float(critic)))
        }

        return RatingDisplayPolicy.apply(
            ratings: result,
            enabledSourcesOrdered: enabledSourcesOrdered,
            enableAdditionalRatings: enableAdditionalRatings,
            isEpisode: item.type == .episode,
            enableEpisodeRatings: episodeRatingsEnabled,
            hasEpisodeRating: false
        )
    }

    func fetchShufflePreviewItems(libraryId: String? = nil, genreName: String? = nil, limit: Int = 5) async -> [ServerItem] {
        guard let client else { return [] }

        let requestedLimit = max(limit, 5)
        let contentType = shuffleContentType
        let selectedLibraryId = normalizedShuffleLibraryId(libraryId, contentType: contentType)
        let includeTypes = contentType.itemTypes
        let genreFilter = genreName.map { [$0] }
        var collected: [ServerItem] = []
        var seenItemIds = Set<String>()

        func appendUniqueItems(_ items: [ServerItem]) {
            for item in items where item.type != .boxSet {
                if seenItemIds.insert(item.id).inserted {
                    collected.append(item)
                }
                if collected.count >= requestedLimit {
                    break
                }
            }
        }

        for _ in 0..<6 {
            do {
                let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                    parentId: selectedLibraryId,
                    recursive: true,
                    includeItemTypes: includeTypes,
                    excludeItemTypes: [.boxSet],
                    sortBy: [.random],
                    fields: [.overview, .genres, .officialRating, .providerIds, .taglines],
                    limit: requestedLimit,
                    genres: genreFilter,
                    enableImages: false,
                    enableUserData: true,
                    enableTotalRecordCount: false
                ))
                appendUniqueItems(result.items)
                if collected.count >= requestedLimit {
                    return Array(collected.prefix(requestedLimit))
                }
            } catch {
                break
            }
        }

        do {
            let countResult = try await client.itemsApi.getItems(request: GetItemsRequest(
                parentId: selectedLibraryId,
                recursive: true,
                includeItemTypes: includeTypes,
                excludeItemTypes: [.boxSet],
                limit: 0,
                genres: genreFilter
            ))
            guard countResult.totalRecordCount > 0 else { return Array(collected.prefix(requestedLimit)) }

            var attemptedIndexes = Set<Int>()
            let maxAttempts = min(countResult.totalRecordCount * 2, requestedLimit * 12)

            while collected.count < requestedLimit, attemptedIndexes.count < maxAttempts {
                let randomIndex = Int.random(in: 0..<countResult.totalRecordCount)
                guard attemptedIndexes.insert(randomIndex).inserted else { continue }

                let itemResult = try await client.itemsApi.getItems(request: GetItemsRequest(
                    parentId: selectedLibraryId,
                    recursive: true,
                    includeItemTypes: includeTypes,
                    excludeItemTypes: [.boxSet],
                    sortBy: [.sortName],
                    fields: [.overview, .genres, .officialRating, .providerIds, .taglines],
                    limit: 1,
                    startIndex: randomIndex,
                    genres: genreFilter,
                    enableImages: false,
                    enableUserData: true,
                    enableTotalRecordCount: false
                ))

                guard let item = itemResult.items.first, item.type != .boxSet else { continue }
                if seenItemIds.insert(item.id).inserted {
                    collected.append(item)
                }
            }

            return Array(collected.prefix(requestedLimit))
        } catch {
            return Array(collected.prefix(requestedLimit))
        }
    }

    func shufflePosterUrl(for item: ServerItem, maxWidth: Int = 520) -> String? {
        guard let client else { return nil }

        if let primaryTag = item.imageTags?["Primary"] {
            return client.imageApi.getItemImageUrl(
                itemId: item.id,
                imageType: .primary,
                maxWidth: maxWidth,
                maxHeight: nil,
                tag: primaryTag
            )
        }

        if let thumbTag = item.imageTags?["Thumb"] {
            return client.imageApi.getItemImageUrl(
                itemId: item.id,
                imageType: .thumb,
                maxWidth: maxWidth,
                maxHeight: nil,
                tag: thumbTag
            )
        }

        if let seriesId = item.seriesId,
           let seriesPrimaryTag = item.seriesPrimaryImageTag {
            return client.imageApi.getItemImageUrl(
                itemId: seriesId,
                imageType: .primary,
                maxWidth: maxWidth,
                maxHeight: nil,
                tag: seriesPrimaryTag
            )
        }

        if let parentThumbItemId = item.parentThumbItemId,
           let parentThumbImageTag = item.parentThumbImageTag {
            return client.imageApi.getItemImageUrl(
                itemId: parentThumbItemId,
                imageType: .thumb,
                maxWidth: maxWidth,
                maxHeight: nil,
                tag: parentThumbImageTag
            )
        }

        if let backdropTag = item.backdropImageTags?.first {
            return client.imageApi.getItemImageUrl(
                itemId: item.id,
                imageType: .backdrop,
                maxWidth: maxWidth,
                maxHeight: nil,
                tag: backdropTag
            )
        }

        return client.imageApi.getItemImageUrl(
            itemId: item.id,
            imageType: .primary,
            maxWidth: maxWidth,
            maxHeight: nil,
            tag: nil
        )
    }

    func fetchGenres(libraryId: String? = nil) async -> [String] {
        guard let client else { return [] }

        let contentType = shuffleContentType
        let selectedLibraryId = normalizedShuffleLibraryId(libraryId, contentType: contentType)
        let includeItemTypes = contentType.itemTypes.map(\.apiValue).joined(separator: ",")

        do {
            let query = buildQuery([
                ("SortBy", "SortName"),
                ("SortOrder", "Ascending"),
                ("ParentId", selectedLibraryId),
                ("Recursive", "true"),
                ("IncludeItemTypes", includeItemTypes),
            ])
            let result: ItemsResult = try await client.httpClient.request("/Genres", queryItems: query)
            let genres = result.items
                .map(\.name)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(genres)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {
            return []
        }
    }

    private func normalizedShuffleLibraryId(_ libraryId: String?, contentType: ShuffleContentType) -> String? {
        guard let libraryId else { return nil }
        let allowedIds = Set(
            userViews
                .filter { isEligibleShuffleLibrary($0, contentType: contentType) }
                .map(\.id)
        )
        return allowedIds.contains(libraryId) ? libraryId : nil
    }

    private func isEligibleShuffleLibrary(_ item: ServerItem, contentType: ShuffleContentType) -> Bool {
        guard let collectionType = item.collectionType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !collectionType.isEmpty else {
            return false
        }

        return allowedShuffleCollectionTypes(for: contentType).contains(collectionType)
    }

    private func allowedShuffleCollectionTypes(for contentType: ShuffleContentType) -> Set<String> {
        switch contentType {
        case .movies:
            return ["movies"]
        case .tvShows:
            return ["tvshows", "series"]
        case .both:
            return ["movies", "tvshows", "series"]
        }
    }

    private func shuffle(contentType: ShuffleContentType, libraryId: String? = nil, genreName: String? = nil) async -> ServerItem? {
        guard !isShuffling, let client else { return nil }
        isShuffling = true
        defer { isShuffling = false }

        let includeTypes = contentType.itemTypes
        let genreFilter = genreName.map { [$0] }

        for _ in 1...5 {
            do {
                let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                    parentId: libraryId,
                    recursive: true,
                    includeItemTypes: includeTypes,
                    excludeItemTypes: [.boxSet],
                    sortBy: [.random],
                    limit: 1,
                    genres: genreFilter,
                    enableImages: false,
                    enableUserData: false,
                    enableTotalRecordCount: false
                ))
                guard let item = result.items.first else { return nil }
                if item.type == .boxSet { continue }
                return item
            } catch {
                break
            }
        }

        do {
            let countResult = try await client.itemsApi.getItems(request: GetItemsRequest(
                parentId: libraryId,
                recursive: true,
                includeItemTypes: includeTypes,
                excludeItemTypes: [.boxSet],
                limit: 0,
                genres: genreFilter
            ))
            guard countResult.totalRecordCount > 0 else { return nil }
            let randomIndex = Int.random(in: 0..<countResult.totalRecordCount)
            let itemResult = try await client.itemsApi.getItems(request: GetItemsRequest(
                parentId: libraryId,
                recursive: true,
                includeItemTypes: includeTypes,
                excludeItemTypes: [.boxSet],
                sortBy: [.sortName],
                limit: 1,
                startIndex: randomIndex,
                genres: genreFilter,
                enableImages: false,
                enableUserData: false,
                enableTotalRecordCount: false
            ))
            return itemResult.items.first
        } catch {
            return nil
        }
    }
}
