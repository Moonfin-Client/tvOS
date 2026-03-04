import Foundation

final class MediaServerClientFactory {
    private var clients: [UUID: MediaServerClient] = [:]

    func client(for server: Server) -> MediaServerClient {
        if let existing = clients[server.id] {
            return existing
        }

        let newClient: MediaServerClient
        switch server.serverType {
        case .jellyfin:
            newClient = JellyfinServerClient()
        case .emby:
            newClient = EmbyServerClient()
        }

        if let url = URL(string: server.address) {
            newClient.configure(baseURL: url, accessToken: nil, userId: nil)
        }

        clients[server.id] = newClient
        return newClient
    }

    func configuredClient(for server: Server, accessToken: String, userId: String) -> MediaServerClient {
        let serverClient = client(for: server)
        if let url = URL(string: server.address) {
            serverClient.configure(baseURL: url, accessToken: accessToken, userId: userId)
        }
        return serverClient
    }

    func removeClient(for serverId: UUID) {
        clients.removeValue(forKey: serverId)
    }

    func removeAll() {
        clients.removeAll()
    }
}
