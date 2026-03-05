import SwiftUI
import Combine

@MainActor
final class MainToolbarViewModel: ObservableObject {
    @Published var userImageUrl: String?
    @Published var userViews: [ServerItem] = []
    @Published var clockBehavior: ClockBehavior = .always

    private let container: AppContainer
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainer) {
        self.container = container
        clockBehavior = container.userPreferences[UserPreferences.clockBehavior]
        observeUser()
    }

    private func observeUser() {
        container.userRepository.currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self else { return }
                if let user {
                    self.loadUserImage(user: user)
                    self.loadUserViews(userId: user.id)
                } else {
                    self.userImageUrl = nil
                    self.userViews = []
                }
            }
            .store(in: &cancellables)
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

    private func loadUserViews(userId: String) {
        Task {
            guard let server = container.serverRepository.currentServer.value else { return }
            let client = container.serverClientFactory.client(for: server)
            do {
                let views = try await client.userViewsApi.getUserViews(userId: userId)
                self.userViews = views
            } catch {
                self.userViews = []
            }
        }
    }

    func switchUser() {
        container.sessionRepository.destroyCurrentSession()
    }
}
