import Foundation

@MainActor
final class ItemMutationService {
    private let serverClientFactory: MediaServerClientFactory
    private let serverRepository: ServerRepositoryProtocol

    init(serverClientFactory: MediaServerClientFactory, serverRepository: ServerRepositoryProtocol) {
        self.serverClientFactory = serverClientFactory
        self.serverRepository = serverRepository
    }

    private var client: MediaServerClient? {
        guard let server = serverRepository.currentServer.value else { return nil }
        return serverClientFactory.client(for: server)
    }

    func setFavorite(itemId: String, isFavorite: Bool) async throws -> UserItemData {
        guard let client, let userId = client.userId else {
            throw ServerError.notConfigured("No active session")
        }
        if isFavorite {
            return try await client.userLibraryApi.markFavorite(itemId: itemId, userId: userId)
        } else {
            return try await client.userLibraryApi.unmarkFavorite(itemId: itemId, userId: userId)
        }
    }

    func setPlayed(itemId: String, isPlayed: Bool) async throws -> UserItemData {
        guard let client, let userId = client.userId else {
            throw ServerError.notConfigured("No active session")
        }
        if isPlayed {
            return try await client.userLibraryApi.markPlayed(itemId: itemId, userId: userId)
        } else {
            return try await client.userLibraryApi.unmarkPlayed(itemId: itemId, userId: userId)
        }
    }
}
