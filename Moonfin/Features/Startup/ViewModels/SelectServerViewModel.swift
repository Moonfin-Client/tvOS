import Foundation
import Combine

@MainActor
final class SelectServerViewModel: ObservableObject {
    @Published var storedServers: [Server] = []
    @Published var serverToDelete: Server? = nil

    private let serverRepository: ServerRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    init(serverRepository: ServerRepositoryProtocol) {
        self.serverRepository = serverRepository

        serverRepository.storedServers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] servers in
                self?.storedServers = servers
            }
            .store(in: &cancellables)
    }

    func loadServers() {
        serverRepository.loadStoredServers()
    }

    func deleteServer(_ server: Server) {
        serverRepository.deleteServer(id: server.id)
    }

    var appVersion: String {
        "\(AppConstants.appName) version \(AppConstants.clientVersion)"
    }
}
