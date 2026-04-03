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
            let restoreCompleted = await raceSessionRestoreAgainstTimeout()
            async let minDelay: Void = Task.sleep(nanoseconds: 2_500_000_000)
            _ = try? await minDelay

            if container.sessionRepository.isAuthenticated,
               container.userRepository.currentUser.value != nil {
                router.switchFlow(to: .main)
                configureCrashReportEndpoint()
                container.serverConnectionMonitor.startMonitoring()
                Task { await container.pluginSyncService.syncOnStartup() }
                return
            }

            if !restoreCompleted {
                container.sessionRepository.destroyCurrentSession()
            }

            if let preferredServerId = preferredStartupServerId() {
                restoredServerId = preferredServerId
            }
            router.switchFlow(to: .startup)
        }
    }

    private func raceSessionRestoreAgainstTimeout() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.container.sessionRepository.restoreSession(destroyOnly: false)
                return true
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: Self.sessionTimeoutNs)
                return false
            }

            let completed = await group.next() ?? false
            group.cancelAll()
            return completed
        }
    }

    private func preferredStartupServerId() -> UUID? {
        switch container.authPreferences.autoLoginBehavior {
        case .specificUser:
            if let serverId = UUID(uuidString: container.authPreferences.autoLoginServerId) {
                return serverId
            }
        case .lastUser:
            break
        case .disabled:
            break
        }

        return UUID(uuidString: container.authPreferences.lastServerId)
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
                let serverId = components.queryItems?.first(where: { $0.name == "serverId" })?.value
                router.navigate(to: .itemDetails(itemId: itemId, serverId: serverId))
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
