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

    init(
        serverRepository: ServerRepositoryProtocol,
        serverClientFactory: MediaServerClientFactory,
        userRepository: UserRepositoryProtocol
    ) {
        self.serverRepository = serverRepository
        self.serverClientFactory = serverClientFactory
        self.userRepository = userRepository
        observeUser()
    }

    private func observeUser() {
        userRepository.currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self else { return }
                if let user {
                    self.fetchViews(userId: user.id)
                } else {
                    self.loadTask?.cancel()
                    self.userViews = []
                }
            }
            .store(in: &cancellables)
    }

    private func fetchViews(userId: String) {
        loadTask?.cancel()
        loadTask = Task {
            guard let server = serverRepository.currentServer.value else { return }
            let client = serverClientFactory.client(for: server)
            do {
                let views = try await client.userViewsApi.getUserViews(userId: userId)
                guard !Task.isCancelled else { return }
                self.userViews = views
            } catch {
                guard !Task.isCancelled else { return }
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
