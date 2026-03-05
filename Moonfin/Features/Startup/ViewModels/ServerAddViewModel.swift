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
        guard case .unableToConnect(let candidates, let errors) = state else { return nil }
        var lines = ["Unable to connect:"]
        for candidate in candidates {
            if let error = errors[candidate] {
                lines.append("\(candidate) — \(error)")
            } else {
                lines.append("\(candidate) — Unknown error")
            }
        }
        return lines.joined(separator: "\n")
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
