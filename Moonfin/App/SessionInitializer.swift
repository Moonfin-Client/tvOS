import Foundation

@MainActor
final class SessionInitializer: ObservableObject {
    @Published var restoredServerId: UUID?

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    private static let sessionTimeoutNs: UInt64 = 15_000_000_000

    func initialize(router: NavigationRouter) {
        Task {
            let restoreTask = Task {
                await container.sessionRepository.restoreSession(destroyOnly: false)
            }

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: Self.sessionTimeoutNs)
                restoreTask.cancel()
            }

            // Wait for whichever finishes first, plus minimum splash delay
            async let minDelay: Void = Task.sleep(nanoseconds: 2_500_000_000)
            _ = await (restoreTask.value, try? minDelay)
            timeoutTask.cancel()

            if container.sessionRepository.isAuthenticated,
               container.userRepository.currentUser.value != nil {
                router.switchFlow(to: .main)
                Task { await container.pluginSyncService.syncOnStartup() }
                configureCrashReportEndpoint()
                container.serverConnectionMonitor.startMonitoring()
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

    func handleUserActivity(_ activity: NSUserActivity, router: NavigationRouter) {
        guard container.sessionRepository.isAuthenticated else { return }
        guard let parsed = SpotlightIndexer.parseUserActivity(activity) else { return }
        router.navigate(to: .itemDetails(itemId: parsed.itemId, serverId: parsed.serverId))
    }

    private func configureCrashReportEndpoint() {
        guard let server = container.serverRepository.currentServer.value,
              let baseURL = URL(string: server.address),
              server.serverType.supports(.clientLog) else { return }
        let client = container.serverClientFactory.client(for: server)
        guard let token = client.accessToken else { return }
        let logUrl = baseURL.appendingPathComponent("/ClientLog/Document").absoluteString
        CrashReporter.shared.updateServerEndpoint(url: logUrl, token: token)
    }
}
