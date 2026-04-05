import Foundation
import Combine

@MainActor
final class UserViewsService: ObservableObject {
    @Published private(set) var userViews: [ServerItem] = []

    private let serverRepository: ServerRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory
    private let userRepository: UserRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var currentContextKey: String?

    init(
        serverRepository: ServerRepositoryProtocol,
        serverClientFactory: MediaServerClientFactory,
        userRepository: UserRepositoryProtocol
    ) {
        self.serverRepository = serverRepository
        self.serverClientFactory = serverClientFactory
        self.userRepository = userRepository
        observeSessionContext()
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
            if !userViews.isEmpty {
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
                self.userViews = views
            } catch {
                guard !Task.isCancelled else { return }
                guard self.currentContextKey == contextKey else { return }
                self.currentContextKey = nil
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
