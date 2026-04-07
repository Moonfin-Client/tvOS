import SwiftUI
import Combine

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
        overlayColor = prefs[UserPreferences.mediaBarOverlayColor].color
        overlayOpacity = Double(prefs[UserPreferences.mediaBarOverlayOpacity]) / 100.0
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

        // In Moonfin mode, repository availability already reflects auth state.
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

    func switchUser() {
        container.sessionRepository.destroyCurrentSession()
    }

    @Published var isShuffling = false

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    func performShuffle(libraryId: String? = nil, genreName: String? = nil, router: NavigationRouter) {
        let contentType = container.userPreferences[UserPreferences.shuffleContentType]
        Task {
            guard let item = await shuffle(contentType: contentType, libraryId: libraryId, genreName: genreName) else { return }
            router.navigatePrimaryToItem(item)
        }
    }

    func fetchGenres() async -> [String] {
        guard let client else { return [] }
        do {
            let query = buildQuery([
                ("SortBy", "SortName"),
                ("SortOrder", "Ascending"),
            ])
            let result: ItemsResult = try await client.httpClient.request("/Genres", queryItems: query)
            return result.items.map(\.name)
        } catch {
            return []
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
