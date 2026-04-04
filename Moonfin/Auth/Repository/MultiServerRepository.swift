import Foundation

struct ServerUserSession {
    let server: Server
    let userId: UUID
    let client: MediaServerClient
}

struct AggregatedLibrary {
    let library: ServerItem
    let server: Server
    let userId: UUID
    let displayName: String
}

protocol MultiServerRepositoryProtocol {
    func getLoggedInServers() async -> [ServerUserSession]
    func getAggregatedLibraries() async -> [AggregatedLibrary]
    func getAggregatedResumeItems(mediaTypes: [MediaType], limit: Int) async -> [ServerItem]
    func getAggregatedNextUpItems(limit: Int) async -> [ServerItem]
    func getAggregatedMergedContinueWatching(limit: Int) async -> [ServerItem]
}

final class MultiServerRepository: MultiServerRepositoryProtocol {
    private let serverRepository: ServerRepositoryProtocol
    private let sessionRepository: SessionRepositoryProtocol
    private let authenticationStore: AuthenticationStore
    private let serverClientFactory: MediaServerClientFactory

    private static let serverTimeoutNs: UInt64 = 8_000_000_000

    private static let defaultFields: [ItemField] = [
        .overview, .genres, .providerIds, .dateCreated
    ]

    init(
        serverRepository: ServerRepositoryProtocol,
        sessionRepository: SessionRepositoryProtocol,
        authenticationStore: AuthenticationStore,
        serverClientFactory: MediaServerClientFactory
    ) {
        self.serverRepository = serverRepository
        self.sessionRepository = sessionRepository
        self.authenticationStore = authenticationStore
        self.serverClientFactory = serverClientFactory
    }

    func getLoggedInServers() async -> [ServerUserSession] {
        let servers = serverRepository.storedServers.value
        let currentSession = sessionRepository.currentSession.value

        var sessions: [ServerUserSession] = []

        for server in servers {
            guard let storeUsers = authenticationStore.getUsers(server.id),
                  !storeUsers.isEmpty else { continue }

            let userId: UUID
            let accessToken: String

            if let cs = currentSession, cs.serverId == server.id,
               let user = storeUsers[cs.userId.uuidString],
               let token = user.accessToken, !token.isEmpty {
                userId = cs.userId
                accessToken = token
            } else if let (uid, token) = mostRecentUserWithToken(storeUsers) {
                userId = uid
                accessToken = token
            } else {
                continue
            }

            let client = serverClientFactory.configuredClient(
                for: server, accessToken: accessToken, userId: userId.uuidString
            )
            sessions.append(ServerUserSession(server: server, userId: userId, client: client))
        }

        if sessions.isEmpty, let cs = currentSession {
            if let server = serverRepository.storedServers.value.first(where: { $0.id == cs.serverId }) {
                let client = serverClientFactory.configuredClient(
                    for: server, accessToken: cs.accessToken, userId: cs.userId.uuidString
                )
                sessions.append(ServerUserSession(server: server, userId: cs.userId, client: client))
            }
        }

        return sessions
    }

    func getAggregatedLibraries() async -> [AggregatedLibrary] {
        let sessions = await getLoggedInServers()
        return await queryAllServers(sessions) { session in
            let views = try await session.client.userViewsApi.getUserViews(userId: session.userId.uuidString)
            let suffix = sessions.count > 1 ? " (\(session.server.name))" : ""
            return views.map { view in
                AggregatedLibrary(
                    library: view,
                    server: session.server,
                    userId: session.userId,
                    displayName: "\(view.name)\(suffix)"
                )
            }
        }.flatMap { $0 }
    }

    func getAggregatedResumeItems(mediaTypes: [MediaType], limit: Int) async -> [ServerItem] {
        let sessions = await getLoggedInServers()
        let allItems = await queryAllServers(sessions) { session in
            let request = GetResumeItemsRequest(
                mediaTypes: mediaTypes,
                fields: Self.defaultFields,
                limit: limit,
                enableImages: true,
                imageTypeLimit: 1
            )
            let result = try await session.client.itemsApi.getResumeItems(request: request)
            return self.stampServerId(result.items, server: session.server)
        }.flatMap { $0 }

        return sortByLastPlayed(allItems, limit: limit)
    }

    func getAggregatedNextUpItems(limit: Int) async -> [ServerItem] {
        let sessions = await getLoggedInServers()
        let allItems = await queryAllServers(sessions) { session in
            let request = GetNextUpRequest(
                fields: Self.defaultFields,
                limit: limit,
                enableImages: true,
                imageTypeLimit: 1
            )
            let result = try await session.client.itemsApi.getNextUp(request: request)
            return self.stampServerId(result.items, server: session.server)
        }.flatMap { $0 }

        return sortByLastPlayed(allItems, limit: limit)
    }

    func getAggregatedMergedContinueWatching(limit: Int) async -> [ServerItem] {
        let sessions = await getLoggedInServers()

        async let resumeTask = queryAllServers(sessions) { session in
            let request = GetResumeItemsRequest(
                mediaTypes: [.video],
                fields: Self.defaultFields,
                limit: limit,
                enableImages: true,
                imageTypeLimit: 1
            )
            let result = try await session.client.itemsApi.getResumeItems(request: request)
            return self.stampServerId(result.items, server: session.server)
        }

        async let nextUpTask = queryAllServers(sessions) { session in
            let request = GetNextUpRequest(
                fields: Self.defaultFields,
                limit: limit,
                enableImages: true,
                imageTypeLimit: 1
            )
            let result = try await session.client.itemsApi.getNextUp(request: request)
            return self.stampServerId(result.items, server: session.server)
        }

        let resumeItems = await resumeTask.flatMap { $0 }
        let nextUpItems = await nextUpTask.flatMap { $0 }

        let resumeIds = Set(resumeItems.map(\.id))
        let deduped = resumeItems + nextUpItems.filter { !resumeIds.contains($0.id) }

        return sortByLastPlayed(deduped, limit: limit)
    }

    private func queryAllServers<T>(
        _ sessions: [ServerUserSession],
        query: @escaping (ServerUserSession) async throws -> T
    ) async -> [T] {
        await withTaskGroup(of: T?.self) { group in
            for session in sessions {
                group.addTask {
                    do {
                        return try await withThrowingTaskGroup(of: T.self) { inner in
                            inner.addTask { try await query(session) }
                            inner.addTask {
                                try await Task.sleep(nanoseconds: Self.serverTimeoutNs)
                                throw CancellationError()
                            }
                            let result = try await inner.next()!
                            inner.cancelAll()
                            return result
                        }
                    } catch {
                        return nil
                    }
                }
            }
            var results: [T] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
    }

    private func stampServerId(_ items: [ServerItem], server: Server) -> [ServerItem] {
        guard items.first?.serverId == nil || items.first?.serverId?.isEmpty == true else { return items }
        return items.map { item in
            var copy = item
            copy.overrideServerId = server.id.uuidString
            return copy
        }
    }

    private func sortByLastPlayed(_ items: [ServerItem], limit: Int) -> [ServerItem] {
        var seriesLastPlayed: [String: Date] = [:]
        for item in items {
            if let sid = item.seriesId, let date = item.userData?.lastPlayedDate {
                if let existing = seriesLastPlayed[sid] {
                    if date > existing { seriesLastPlayed[sid] = date }
                } else {
                    seriesLastPlayed[sid] = date
                }
            }
        }

        let sorted = items.sorted { a, b in
            let dateA = a.userData?.lastPlayedDate
                ?? a.seriesId.flatMap { seriesLastPlayed[$0] }
                ?? Date.distantPast
            let dateB = b.userData?.lastPlayedDate
                ?? b.seriesId.flatMap { seriesLastPlayed[$0] }
                ?? Date.distantPast
            return dateA > dateB
        }
        return Array(sorted.prefix(limit))
    }

    private func mostRecentUserWithToken(_ users: [String: AuthenticationStore.AuthStoreUser]) -> (UUID, String)? {
        var bestMatch: (uuid: UUID, token: String, lastUsed: Date)?

        for (key, user) in users {
            guard let token = user.accessToken,
                  !token.isEmpty,
                  let uuid = UUID(uuidString: key) else {
                continue
            }

            let candidateLastUsed = user.lastUsed ?? .distantPast
            if let currentBest = bestMatch {
                if candidateLastUsed > currentBest.lastUsed {
                    bestMatch = (uuid, token, candidateLastUsed)
                }
            } else {
                bestMatch = (uuid, token, candidateLastUsed)
            }
        }

        return bestMatch.map { ($0.uuid, $0.token) }
    }
}
