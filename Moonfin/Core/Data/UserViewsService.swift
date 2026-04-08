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
