import Foundation

@MainActor
final class ServerAddViewModel: ObservableObject {
    @Published var address = ""
    @Published var state: ServerAdditionState? = nil
    @Published var isConnecting = false

    private let serverRepository: ServerRepositoryProtocol

    init(serverRepository: ServerRepositoryProtocol) {
        self.serverRepository = serverRepository
    }

    var errorMessage: String? {
        guard case .unableToConnect(let candidates) = state else { return nil }
        return "Unable to connect. Tried:\n" + candidates.joined(separator: "\n")
    }

    func connect() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isConnecting = true
        state = nil

        Task {
            for await update in serverRepository.addServer(address: trimmed) {
                self.state = update

                switch update {
                case .connecting:
                    break
                case .connected, .unableToConnect:
                    isConnecting = false
                }
            }
        }
    }
}
