import SwiftUI
import Combine

@MainActor
final class NavbarViewModel: ObservableObject {
    @Published var userImageUrl: String?
    @Published var userName: String = ""
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
                    self.userName = user.name
                    self.loadUserImage(user: user)
                    self.loadUserViews(userId: user.id)
                } else {
                    self.userName = ""
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

    @Published var isShuffling = false

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    func performQuickShuffle(router: NavigationRouter) {
        let contentType = container.userPreferences[UserPreferences.shuffleContentType]
        Task {
            guard let item = await shuffle(contentType: contentType) else { return }
            router.navigate(to: .itemDetails(itemId: item.id))
        }
    }

    func performShuffle(contentType: ShuffleContentType, router: NavigationRouter) {
        container.userPreferences[UserPreferences.shuffleContentType] = contentType
        Task {
            guard let item = await shuffle(contentType: contentType) else { return }
            router.navigate(to: .itemDetails(itemId: item.id))
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
