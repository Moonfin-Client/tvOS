import Foundation

struct EmbyConnectUser: Codable {
    let id: String
    let name: String
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case email = "Email"
    }
}

struct EmbyConnectAuthResult: Codable {
    let accessToken: String
    let user: EmbyConnectUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

struct EmbyConnectServer: Codable, Identifiable {
    let accessKey: String
    let systemId: String
    let name: String
    let url: String?
    let localAddress: String?

    var id: String { systemId }

    var bestAddress: String? {
        url ?? localAddress
    }

    enum CodingKeys: String, CodingKey {
        case accessKey = "AccessKey"
        case systemId = "SystemId"
        case name = "Name"
        case url = "Url"
        case localAddress = "LocalAddress"
    }
}

struct EmbyConnectExchangeResult: Codable {
    let localUserId: String
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case localUserId = "LocalUserId"
        case accessToken = "AccessToken"
    }
}

enum EmbyConnectError: LocalizedError {
    case invalidCredentials
    case noServersLinked
    case exchangeFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid Emby Connect credentials"
        case .noServersLinked: return "No servers linked to this account"
        case .exchangeFailed: return "Failed to connect to server"
        case .networkError(let msg): return msg
        }
    }
}

final class EmbyConnectService {
    private static let connectBaseURL = "https://connect.emby.media/service"
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let appHeader: String = "\(AppConstants.clientName)/\(AppConstants.clientVersion)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func authenticate(username: String, password: String) async throws -> EmbyConnectAuthResult {
        let url = URL(string: "\(Self.connectBaseURL)/user/authenticate")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appHeader, forHTTPHeaderField: "X-Application")

        struct Body: Encodable { let nameOrEmail: String; let rawpw: String }
        request.httpBody = try encoder.encode(Body(nameOrEmail: username, rawpw: password))

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw EmbyConnectError.networkError("No response")
        }

        if http.statusCode == 401 || http.statusCode == 400 {
            throw EmbyConnectError.invalidCredentials
        }

        guard (200...299).contains(http.statusCode) else {
            throw EmbyConnectError.networkError("HTTP \(http.statusCode)")
        }

        return try decoder.decode(EmbyConnectAuthResult.self, from: data)
    }

    func getServers(connectUserId: String, connectAccessToken: String) async throws -> [EmbyConnectServer] {
        var components = URLComponents(string: "\(Self.connectBaseURL)/servers")!
        components.queryItems = [URLQueryItem(name: "userId", value: connectUserId)]

        var request = URLRequest(url: components.url!)
        request.setValue(appHeader, forHTTPHeaderField: "X-Application")
        request.setValue(connectAccessToken, forHTTPHeaderField: "X-Connect-UserToken")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw EmbyConnectError.networkError("Failed to fetch servers")
        }

        let servers = try decoder.decode([EmbyConnectServer].self, from: data)
        if servers.isEmpty { throw EmbyConnectError.noServersLinked }
        return servers
    }

    func exchange(
        serverAddress: String,
        connectUserId: String,
        accessKey: String
    ) async throws -> EmbyConnectExchangeResult {
        var components = URLComponents(string: "\(serverAddress)/Connect/Exchange")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "ConnectUserId", value: connectUserId),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(accessKey, forHTTPHeaderField: "X-Emby-Token")

        let authParts = [
            "Emby Client=\"\(AppConstants.clientName)\"",
            "Device=\"\(AppConstants.deviceName)\"",
            "DeviceId=\"\(AppConstants.deviceId)\"",
            "Version=\"\(AppConstants.clientVersion)\""
        ]
        request.setValue(authParts.joined(separator: ", "), forHTTPHeaderField: "X-Emby-Authorization")

        let trustDelegate = SSLTrustDelegate()
        let customSession = URLSession(
            configuration: .default,
            delegate: trustDelegate,
            delegateQueue: nil
        )
        defer { customSession.invalidateAndCancel() }

        let (data, response) = try await customSession.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw EmbyConnectError.exchangeFailed
        }

        return try decoder.decode(EmbyConnectExchangeResult.self, from: data)
    }
}
