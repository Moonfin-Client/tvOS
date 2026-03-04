import Foundation

final class JellyfinClient {
    var baseURL: URL?
    var accessToken: String?
    let deviceId: String
    let deviceName: String

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(
        baseURL: URL? = nil,
        accessToken: String? = nil,
        deviceId: String = AppConstants.deviceId,
        deviceName: String = AppConstants.deviceName,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.session = session
    }

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil
    ) async throws -> T {
        let data = try await performRequest(path, method: method, queryItems: queryItems, body: body)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    func requestVoid(
        _ path: String,
        method: String = "POST",
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil
    ) async throws {
        _ = try await performRequest(path, method: method, queryItems: queryItems, body: body)
    }

    private func performRequest(
        _ path: String,
        method: String,
        queryItems: [URLQueryItem]?,
        body: (any Encodable)?
    ) async throws -> Data {
        guard let baseURL else { throw NetworkError.invalidURL }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.serverUnavailable
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            throw NetworkError.httpError(statusCode: http.statusCode, data: data)
        }

        return data
    }

    private var authorizationHeader: String {
        var parts = [
            "MediaBrowser Client=\"\(AppConstants.clientName)\"",
            "Device=\"\(deviceName)\"",
            "DeviceId=\"\(deviceId)\"",
            "Version=\"\(AppConstants.clientVersion)\""
        ]
        if let accessToken {
            parts.append("Token=\"\(accessToken)\"")
        }
        return parts.joined(separator: ", ")
    }
}
