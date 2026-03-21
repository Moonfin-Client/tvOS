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
    @Published var seerrDisplayName: String = "Jellyseerr"
    @Published var seerrIconName: String = "jellyseerr"

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
            let enabled = seerrPrefs[SeerrPreferences.enabled]
            showSeerrInNavigation = enabled && available && seerrPrefs[SeerrPreferences.showInNavigation]
            showSeerrInToolbar = enabled && available && seerrPrefs[SeerrPreferences.showInToolbar]

            let variant = seerrPrefs[SeerrPreferences.moonfinVariant]
            let dn = seerrPrefs[SeerrPreferences.moonfinDisplayName]
            seerrDisplayName = dn.isEmpty ? (variant == "seerr" ? "Seerr" : "Jellyseerr") : dn
            seerrIconName = variant == "seerr" ? "seerr" : "jellyseerr"
        } else {
            showSeerrInNavigation = false
            showSeerrInToolbar = false
            seerrDisplayName = "Jellyseerr"
            seerrIconName = "jellyseerr"
        }
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

    func performQuickShuffle(router: NavigationRouter) {
        let contentType = container.userPreferences[UserPreferences.shuffleContentType]
        Task {
            guard let item = await shuffle(contentType: contentType) else { return }
            router.navigatePrimary(to: .itemDetails(itemId: item.id))
        }
    }

    func performShuffle(contentType: ShuffleContentType, router: NavigationRouter) {
        container.userPreferences[UserPreferences.shuffleContentType] = contentType
        Task {
            guard let item = await shuffle(contentType: contentType) else { return }
            router.navigatePrimary(to: .itemDetails(itemId: item.id))
        }
    }

    private func shuffle(contentType: ShuffleContentType, libraryId: String? = nil) async -> ServerItem? {
        guard !isShuffling, let client else { return nil }
        isShuffling = true
        defer { isShuffling = false }

        let includeTypes = contentType.itemTypes

        for _ in 1...5 {
            do {
                let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                    parentId: libraryId,
                    recursive: true,
                    includeItemTypes: includeTypes,
                    excludeItemTypes: [.boxSet],
                    sortBy: [.random],
                    limit: 1
                ))
                guard let item = result.items.first else { return nil }
                if item.type == .boxSet { continue }
                return item
            } catch {
                break
            }
        }

        // Client-side fallback when server-side Random sort fails
        do {
            let countResult = try await client.itemsApi.getItems(request: GetItemsRequest(
                parentId: libraryId,
                recursive: true,
                includeItemTypes: includeTypes,
                excludeItemTypes: [.boxSet],
                limit: 0
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
                startIndex: randomIndex
            ))
            return itemResult.items.first
        } catch {
            return nil
        }
    }
}
