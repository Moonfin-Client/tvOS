import Foundation

@MainActor
final class SessionInitializer: ObservableObject {
    @Published var restoredServerId: UUID?

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    func initialize(router: NavigationRouter) {
        Task {
            async let restore: Void = container.sessionRepository.restoreSession(destroyOnly: false)
            async let minDelay: Void = Task.sleep(nanoseconds: 2_500_000_000)

            _ = await (restore, try? minDelay)

            if container.sessionRepository.isAuthenticated,
               container.userRepository.currentUser.value != nil {
                router.switchFlow(to: .main)
                return
            }

            if let lastServerId = UUID(uuidString: container.authPreferences.lastServerId) {
                restoredServerId = lastServerId
            }
            router.switchFlow(to: .startup)
        }
    }

    func handleDeepLink(url: URL, router: NavigationRouter) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme == "moonfin" else { return }

        guard container.sessionRepository.isAuthenticated else { return }

        switch components.host {
        case "search":
            let query = components.queryItems?.first(where: { $0.name == "query" })?.value
            router.navigate(to: .search(query: query))
        case "item":
            if let itemId = components.queryItems?.first(where: { $0.name == "id" })?.value {
                router.navigate(to: .itemDetails(itemId: itemId))
            }
        default:
            break
        }
    }
}
