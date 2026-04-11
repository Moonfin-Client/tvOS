import Foundation
import os

final class SeerrHttpClient {
    private let baseUrl: String
    private let apiKey: String
    private let session: URLSession
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "Seerr")

    var proxyConfig: MoonfinProxyConfig?
    var isProxyMode: Bool { proxyConfig != nil }

    private static let requestTimeout: TimeInterval = 30
    private static var cookieStorages: [String: HTTPCookieStorage] = [:]
    private static var activeCookieStorage: HTTPCookieStorage?

    private let decoder = JSONDecoder()

    private let encoder = JSONEncoder()

    init(baseUrl: String, apiKey: String = "", proxyConfig: MoonfinProxyConfig? = nil) {
        self.baseUrl = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.proxyConfig = proxyConfig

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = Self.requestTimeout
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        if let storage = Self.activeCookieStorage {
            config.httpCookieStorage = storage
        }
        self.session = URLSession(configuration: config)
    }

    // MARK: - Cookie Management

    static func switchCookieStorage(userId: String) {
        if let existing = cookieStorages[userId] {
            activeCookieStorage = existing
        } else {
            let storage = HTTPCookieStorage()
            cookieStorages[userId] = storage
            activeCookieStorage = storage
        }
    }

    static func clearCookies() {
        activeCookieStorage?.cookies?.forEach { activeCookieStorage?.deleteCookie($0) }
    }

    // MARK: - URL Routing

    private func apiUrl(_ path: String) -> String {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if let proxy = proxyConfig {
            return "\(proxy.jellyfinBaseUrl)/Moonfin/Jellyseerr/Api/\(trimmed)"
        }
        return "\(baseUrl)/api/v1/\(trimmed)"
    }

    private func moonfinUrl(_ path: String) -> String {
        guard let proxy = proxyConfig else { fatalError("Moonfin proxy not configured") }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return "\(proxy.jellyfinBaseUrl)/Moonfin/Jellyseerr/\(trimmed)"
    }

    // MARK: - Auth & CSRF

    private func addAuthHeaders(to request: inout URLRequest) {
        if let proxy = proxyConfig {
            request.setValue("MediaBrowser Token=\"\(proxy.jellyfinToken)\"", forHTTPHeaderField: "Authorization")
        } else if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
    }

    private func fetchCsrfToken(endpoint: String) async -> String? {
        guard !isProxyMode else { return nil }
        guard let url = URL(string: "\(baseUrl)\(endpoint)") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(to: &request)

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            let cookieStorage = session.configuration.httpCookieStorage ?? .shared
            if let cookies = cookieStorage.cookies(for: url) {
                for cookie in cookies where cookie.name == "XSRF-TOKEN" {
                    return cookie.value
                }
            }

            if let setCookieHeaders = httpResponse.allHeaderFields["Set-Cookie"] as? String {
                return parseCsrfFromHeader(setCookieHeaders)
            }
            if let setCookieHeaders = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
                return parseCsrfFromHeader(setCookieHeaders)
            }
        } catch {
            logger.warning("Failed to fetch CSRF token: \(error.localizedDescription)")
        }
        return nil
    }

    private func parseCsrfFromHeader(_ header: String) -> String? {
        for part in header.split(separator: ",") {
            let cookiePart = part.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            let kv = cookiePart.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == "XSRF-TOKEN" {
                return String(kv[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func addCsrfHeaders(to request: inout URLRequest, token: String?) {
        guard let token else { return }
        request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
        request.setValue(token, forHTTPHeaderField: "X-XSRF-TOKEN")
    }

    // MARK: - Base Request Helpers

    private func get<T: Decodable>(url urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(to: &request)
        return try await perform(request)
    }

    private func post<T: Decodable>(url urlString: String, body: (any Encodable)? = nil, csrfEndpoint: String? = nil) async throws -> T {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        let csrfToken = if let ep = csrfEndpoint { await fetchCsrfToken(endpoint: ep) } else { nil as String? }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(to: &request)
        addCsrfHeaders(to: &request, token: csrfToken)
        if let body { request.httpBody = try encoder.encode(body) }
        return try await perform(request)
    }

    private func delete(url urlString: String, csrfEndpoint: String? = nil) async throws {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        let csrfToken = if let ep = csrfEndpoint { await fetchCsrfToken(endpoint: ep) } else { nil as String? }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeaders(to: &request)
        addCsrfHeaders(to: &request, token: csrfToken)
        try await performVoid(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await performRaw(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    private func performVoid(_ request: URLRequest) async throws {
        _ = try await performRaw(request)
    }

    private func performRaw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.serverUnavailable }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            throw NetworkError.httpError(statusCode: http.statusCode, data: data)
        }
        return unwrapProxyEnvelope(data, url: request.url)
    }

    private func unwrapProxyEnvelope(_ data: Data, url: URL?) -> Data {
        guard let url, url.path.contains("/Moonfin/Jellyseerr/Api/") else { return data }
        guard let str = String(data: data, encoding: .utf8),
              str.trimmingCharacters(in: .whitespaces).hasPrefix("{\"FileContents\"") else { return data }
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let base64 = json["FileContents"] as? String,
               let decoded = Data(base64Encoded: base64) {
                return decoded
            }
        } catch {}
        return data
    }

    // MARK: - URL Builder

    private func buildUrl(_ base: String, params: [String: String] = [:]) -> String {
        guard !params.isEmpty else { return base }
        var components = URLComponents(string: base)
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.string ?? base
    }

    // MARK: - Requests

    func getRequests(
        filter: String? = nil,
        requestedBy: Int? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SeerrListResponse<SeerrRequestDto> {
        var params: [String: String] = [
            "skip": String(offset),
            "take": String(limit)
        ]
        if let filter { params["filter"] = filter }
        if let requestedBy { params["requestedBy"] = String(requestedBy) }
        return try await get(url: buildUrl(apiUrl("request"), params: params))
    }

    func getRequest(requestId: Int) async throws -> SeerrRequestDto {
        try await get(url: apiUrl("request/\(requestId)"))
    }

    func createRequest(
        mediaId: Int,
        mediaType: String,
        seasons: SeerrSeasons? = nil,
        is4k: Bool = false,
        profileId: Int? = nil,
        rootFolderId: Int? = nil,
        serverId: Int? = nil
    ) async throws -> SeerrRequestDto {
        let seasonsValue = (mediaType == "tv" && seasons == nil) ? SeerrSeasons.all : seasons
        let body = SeerrCreateRequestBody(
            mediaId: mediaId,
            mediaType: mediaType,
            seasons: seasonsValue,
            is4k: is4k,
            profileId: profileId,
            rootFolderId: rootFolderId,
            serverId: serverId
        )
        return try await post(
            url: apiUrl("request"),
            body: body,
            csrfEndpoint: isProxyMode ? nil : "/api/v1/request"
        )
    }

    func deleteRequest(requestId: Int) async throws {
        try await delete(
            url: apiUrl("request/\(requestId)"),
            csrfEndpoint: isProxyMode ? nil : "/api/v1/request/\(requestId)"
        )
    }

    // MARK: - Discovery

    func getTrending(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        let page = (offset / limit) + 1
        return try await get(url: buildUrl(apiUrl("discover/trending"), params: [
            "page": String(page), "language": "en"
        ]))
    }

    func getTrendingMovies(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        let page = (offset / limit) + 1
        return try await get(url: buildUrl(apiUrl("discover/movies"), params: [
            "page": String(page), "language": "en"
        ]))
    }

    func getTrendingTv(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        let page = (offset / limit) + 1
        return try await get(url: buildUrl(apiUrl("discover/tv"), params: [
            "page": String(page), "language": "en"
        ]))
    }

    func getTopMovies(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        try await get(url: buildUrl(apiUrl("discover/movies/top"), params: [
            "limit": String(limit), "offset": String(offset)
        ]))
    }

    func getTopTv(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        try await get(url: buildUrl(apiUrl("discover/tv/top"), params: [
            "limit": String(limit), "offset": String(offset)
        ]))
    }

    func getUpcomingMovies() async throws -> SeerrDiscoverPageDto {
        try await get(url: apiUrl("discover/movies/upcoming"))
    }

    func getUpcomingTv() async throws -> SeerrDiscoverPageDto {
        try await get(url: apiUrl("discover/tv/upcoming"))
    }

    func getRecentlyAdded(limit: Int = 20) async throws -> SeerrListResponse<SeerrMediaDto> {
        try await get(url: buildUrl(apiUrl("media"), params: [
            "filter": "allavailable", "sort": "mediaAdded", "take": String(limit)
        ]))
    }

    // MARK: - Search

    func search(query: String, mediaType: String? = nil, limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        let page = (offset / limit) + 1
        var params: [String: String] = [
            "query": query,
            "page": String(page)
        ]
        if let mediaType { params["type"] = mediaType }
        return try await get(url: buildUrl(apiUrl("search"), params: params))
    }

    // MARK: - Similar & Recommendations

    func getSimilarMovies(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverPageDto {
        try await get(url: buildUrl(apiUrl("movie/\(tmdbId)/similar"), params: ["page": String(page)]))
    }

    func getSimilarTv(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverPageDto {
        try await get(url: buildUrl(apiUrl("tv/\(tmdbId)/similar"), params: ["page": String(page)]))
    }

    func getRecommendationsMovies(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverPageDto {
        try await get(url: buildUrl(apiUrl("movie/\(tmdbId)/recommendations"), params: ["page": String(page)]))
    }

    func getRecommendationsTv(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverPageDto {
        try await get(url: buildUrl(apiUrl("tv/\(tmdbId)/recommendations"), params: ["page": String(page)]))
    }

    // MARK: - Genre Sliders

    func getGenreSliderMovies() async throws -> [SeerrGenreDto] {
        try await get(url: apiUrl("discover/genreslider/movie"))
    }

    func getGenreSliderTv() async throws -> [SeerrGenreDto] {
        try await get(url: apiUrl("discover/genreslider/tv"))
    }

    // MARK: - Discover with Filters

    func discoverMovies(
        page: Int = 1,
        sortBy: String = "popularity.desc",
        genre: Int? = nil,
        studio: Int? = nil,
        keywords: Int? = nil,
        language: String = "en"
    ) async throws -> SeerrDiscoverPageDto {
        var params: [String: String] = [
            "page": String(page),
            "sortBy": sortBy,
            "language": language
        ]
        if let genre { params["genre"] = String(genre) }
        if let studio { params["studio"] = String(studio) }
        if let keywords { params["keywords"] = String(keywords) }
        return try await get(url: buildUrl(apiUrl("discover/movies"), params: params))
    }

    func discoverTv(
        page: Int = 1,
        sortBy: String = "popularity.desc",
        genre: Int? = nil,
        network: Int? = nil,
        keywords: Int? = nil,
        language: String = "en"
    ) async throws -> SeerrDiscoverPageDto {
        var params: [String: String] = [
            "page": String(page),
            "sortBy": sortBy,
            "language": language
        ]
        if let genre { params["genre"] = String(genre) }
        if let network { params["network"] = String(network) }
        if let keywords { params["keywords"] = String(keywords) }
        return try await get(url: buildUrl(apiUrl("discover/tv"), params: params))
    }

    // MARK: - Person

    func getPersonDetails(personId: Int) async throws -> SeerrPersonDetailsDto {
        try await get(url: apiUrl("person/\(personId)"))
    }

    func getPersonCombinedCredits(personId: Int) async throws -> SeerrPersonCombinedCreditsDto {
        try await get(url: apiUrl("person/\(personId)/combined_credits"))
    }

    // MARK: - Media Details

    func getMovieDetails(tmdbId: Int) async throws -> SeerrMovieDetailsDto {
        try await get(url: apiUrl("movie/\(tmdbId)"))
    }

    func getTvDetails(tmdbId: Int) async throws -> SeerrTvDetailsDto {
        try await get(url: apiUrl("tv/\(tmdbId)"))
    }

    // MARK: - Authentication

    func loginLocal(email: String, password: String) async throws -> SeerrUserDto {
        Self.clearCookies()
        let csrfToken = await fetchCsrfToken(endpoint: "/api/v1/auth/local")
        try? await Task.sleep(nanoseconds: 100_000_000)

        let body: [String: String] = ["email": email, "password": password]
        guard let url = URL(string: apiUrl("auth/local")) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addCsrfHeaders(to: &request, token: csrfToken)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.serverUnavailable }

        if http.statusCode == 308,
           let location = http.value(forHTTPHeaderField: "Location"),
           location.hasPrefix("https://"), baseUrl.hasPrefix("http://") {
            guard let retryUrl = URL(string: location) else { throw NetworkError.invalidURL }
            var retryRequest = URLRequest(url: retryUrl)
            retryRequest.httpMethod = "POST"
            retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            addCsrfHeaders(to: &retryRequest, token: csrfToken)
            retryRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            let retryData = try await performRaw(retryRequest)
            return try decoder.decode(SeerrUserDto.self, from: retryData)
        }

        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.httpError(statusCode: http.statusCode, data: data)
        }
        let unwrapped = unwrapProxyEnvelope(data, url: url)
        return try decoder.decode(SeerrUserDto.self, from: unwrapped)
    }

    func loginJellyfin(username: String, password: String, jellyfinUrl: String) async throws -> SeerrUserDto {
        Self.clearCookies()
        let csrfToken = await fetchCsrfToken(endpoint: "/api/v1/auth/jellyfin")
        try? await Task.sleep(nanoseconds: 100_000_000)

        var urlString = apiUrl("auth/jellyfin")
        let body: [String: String] = ["username": username, "password": password]

        guard var url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addCsrfHeaders(to: &request, token: csrfToken)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var (data, response) = try await session.data(for: request)
        guard var http = response as? HTTPURLResponse else { throw NetworkError.serverUnavailable }

        if http.statusCode == 308,
           let location = http.value(forHTTPHeaderField: "Location"),
           location.hasPrefix("https://"), baseUrl.hasPrefix("http://") {
            guard let httpsUrl = URL(string: location) else { throw NetworkError.invalidURL }
            url = httpsUrl
            urlString = location
            var retryRequest = URLRequest(url: httpsUrl)
            retryRequest.httpMethod = "POST"
            retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            addCsrfHeaders(to: &retryRequest, token: csrfToken)
            retryRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            (data, response) = try await session.data(for: retryRequest)
            guard let updatedHttp = response as? HTTPURLResponse else { throw NetworkError.serverUnavailable }
            http = updatedHttp
        }

        if (200...299).contains(http.statusCode) {
            let unwrapped = unwrapProxyEnvelope(data, url: url)
            return try decoder.decode(SeerrUserDto.self, from: unwrapped)
        }

        if http.statusCode == 401 {
            let bodyWithHost: [String: String] = [
                "username": username,
                "password": password,
                "hostname": jellyfinUrl
            ]
            guard let retryUrl = URL(string: urlString) else { throw NetworkError.invalidURL }
            var retryRequest = URLRequest(url: retryUrl)
            retryRequest.httpMethod = "POST"
            retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            addCsrfHeaders(to: &retryRequest, token: csrfToken)
            retryRequest.httpBody = try JSONSerialization.data(withJSONObject: bodyWithHost)
            let retryData = try await performRaw(retryRequest)
            return try decoder.decode(SeerrUserDto.self, from: retryData)
        }

        throw NetworkError.httpError(statusCode: http.statusCode, data: data)
    }

    func getCurrentUser() async throws -> SeerrUserDto {
        try await get(url: apiUrl("auth/me"))
    }

    // MARK: - Admin

    func regenerateApiKey() async throws -> String {
        let settings: SeerrMainSettingsDto = try await post(
            url: apiUrl("settings/main/regenerate"),
            csrfEndpoint: isProxyMode ? nil : "/api/v1/settings/main/regenerate"
        )
        return settings.apiKey
    }

    // MARK: - Status & Configuration

    func getStatus() async throws -> SeerrStatusDto {
        try await get(url: apiUrl("status"))
    }

    func testConnection() async throws -> Bool {
        do {
            let _: SeerrStatusDto = try await get(url: apiUrl("status"))
            return true
        } catch {
            return false
        }
    }

    // MARK: - Service Configuration

    func getRadarrServers() async throws -> [SeerrServiceServerDto] {
        try await get(url: apiUrl("service/radarr"))
    }

    func getRadarrServerDetails(serverId: Int) async throws -> SeerrServiceServerDetailsDto {
        try await get(url: apiUrl("service/radarr/\(serverId)"))
    }

    func getSonarrServers() async throws -> [SeerrServiceServerDto] {
        try await get(url: apiUrl("service/sonarr"))
    }

    func getSonarrServerDetails(serverId: Int) async throws -> SeerrServiceServerDetailsDto {
        try await get(url: apiUrl("service/sonarr/\(serverId)"))
    }

    func getRadarrSettings() async throws -> [SeerrRadarrSettingsDto] {
        try await get(url: apiUrl("settings/radarr"))
    }

    func getSonarrSettings() async throws -> [SeerrSonarrSettingsDto] {
        try await get(url: apiUrl("settings/sonarr"))
    }

    // MARK: - Moonfin Plugin SSO

    func getMoonfinStatus() async throws -> MoonfinStatusResponse {
        try await get(url: moonfinUrl("Status"))
    }

    func moonfinLogin(username: String, password: String, authType: String = "jellyfin") async throws -> MoonfinLoginResponse {
        let body = MoonfinLoginRequest(username: username, password: password, authType: authType)
        let result: MoonfinLoginResponse = try await post(url: moonfinUrl("Login"), body: body)
        guard result.success else { throw SeerrError.moonfinLoginFailed(result.error ?? "Unknown error") }
        return result
    }

    func moonfinLogout() async throws {
        try await delete(url: moonfinUrl("Logout"))
    }

    func moonfinValidate() async throws -> MoonfinValidateResponse {
        try await get(url: moonfinUrl("Validate"))
    }
}

// MARK: - Error

enum SeerrError: LocalizedError {
    case moonfinLoginFailed(String)

    var errorDescription: String? {
        switch self {
        case .moonfinLoginFailed(let msg): return "Moonfin login failed: \(msg)"
        }
    }
}
