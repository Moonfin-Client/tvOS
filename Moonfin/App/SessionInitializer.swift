import Foundation

@MainActor
final class SessionInitializer: ObservableObject {
    @Published var restoredServerId: UUID?
    var suppressAutoLogin = false

    func consumeSuppressAutoLogin() -> Bool {
        let value = suppressAutoLogin
        suppressAutoLogin = false
        return value
    }

    private let container: AppContainer
    private var pendingDestination: Destination?

    init(container: AppContainer) {
        self.container = container
    }

    private static let sessionTimeoutNs: UInt64 = 15_000_000_000
    private static let splashMinNs: UInt64 = 2_500_000_000
    private static let syncGraceNs: UInt64 = 2_500_000_000

    func initialize(router: NavigationRouter) {
        Task {
            let restoreCompleted = await raceSessionRestoreAgainstTimeout()

            if container.sessionRepository.isAuthenticated,
               container.userRepository.currentUser.value != nil {
                // Run plugin sync during splash so preferences land before home loads
                let syncTask = Task { await container.pluginSyncService.syncOnStartup() }
                try? await Task.sleep(nanoseconds: Self.splashMinNs)
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await syncTask.value }
                    group.addTask { try? await Task.sleep(nanoseconds: Self.syncGraceNs) }
                    await group.next()
                    group.cancelAll()
                }
                router.switchFlow(to: .main)
                processPendingDestinationIfPossible(router: router)
                configureCrashReportEndpoint()
                container.serverConnectionMonitor.startMonitoring()
                return
            }

            try? await Task.sleep(nanoseconds: Self.splashMinNs)

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
        guard let destination = destination(from: url) else { return }
        navigateOrQueue(destination: destination, router: router)
    }

    func handleUserActivity(_ activity: NSUserActivity, router: NavigationRouter) {
        guard let parsed = SpotlightIndexer.parseUserActivity(activity) else { return }
        navigateOrQueue(destination: .itemDetails(itemId: parsed.itemId, serverId: parsed.serverId), router: router)
    }

    private func destination(from url: URL) -> Destination? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme == "moonfin" else { return nil }

        switch components.host {
        case "search":
            let query = components.queryItems?.first(where: { $0.name == "query" })?.value
            return .search(query: query)
        case "item":
            guard let itemId = components.queryItems?.first(where: { $0.name == "id" })?.value else { return nil }
            let serverId = components.queryItems?.first(where: { $0.name == "serverId" })?.value
            return .itemDetails(itemId: itemId, serverId: serverId)
        default:
            return nil
        }
    }

    private func navigateOrQueue(destination: Destination, router: NavigationRouter) {
        guard container.sessionRepository.isAuthenticated,
              container.userRepository.currentUser.value != nil else {
            pendingDestination = destination
            return
        }
        router.navigate(to: destination)
    }

    private func processPendingDestinationIfPossible(router: NavigationRouter) {
        guard let destination = pendingDestination,
              container.sessionRepository.isAuthenticated,
              container.userRepository.currentUser.value != nil else { return }
        pendingDestination = nil
        router.navigate(to: destination)
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
