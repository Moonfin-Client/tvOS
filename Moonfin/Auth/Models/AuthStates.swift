import Foundation

enum LoginState: Equatable {
    case idle
    case authenticating
    case requireSignIn
    case serverUnavailable
    case versionNotSupported(Server)
    case apiClientError(String)
    case authenticated
}

enum QuickConnectState: Equatable {
    case unknown
    case unavailable
    case pending(code: String)
    case connected
}

enum ServerAdditionState: Equatable {
    case connecting(address: String)
    case unableToConnect(candidates: [String])
    case connected(id: UUID, name: String)
}

enum AuthenticateMethod {
    case automatic(user: any User)
    case credentials(username: String, password: String)
    case quickConnect(secret: String)
}
