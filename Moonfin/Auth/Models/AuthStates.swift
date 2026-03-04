import Foundation

enum LoginState {
    case idle
    case authenticating
    case requireSignIn
    case serverUnavailable
    case versionNotSupported(Server)
    case apiClientError(Error)
    case authenticated
}

enum QuickConnectState {
    case unknown
    case unavailable
    case pending(code: String)
    case connected
}

enum ServerAdditionState {
    case connecting(address: String)
    case unableToConnect(candidates: [String])
    case connected(id: UUID, name: String)
}
