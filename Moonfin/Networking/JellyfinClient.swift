import Foundation

final class JellyfinClient {
    var baseURL: URL?
    var accessToken: String?
    let deviceId: String
    let deviceName: String

    private let session: URLSession

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
        guard let baseURL else { throw NetworkError.invalidURL }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.serverUnavailable
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            throw NetworkError.httpError(statusCode: http.statusCode, data: data)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
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
        guard let baseURL else { throw NetworkError.invalidURL }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.serverUnavailable
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            throw NetworkError.httpError(statusCode: http.statusCode, data: data)
        }
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
