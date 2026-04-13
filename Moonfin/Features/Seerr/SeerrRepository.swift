import Foundation
import Combine
import os

protocol SeerrRepositoryProtocol: AnyObject {
    var isAvailable: CurrentValueSubject<Bool, Never> { get }
    var isMoonfinMode: CurrentValueSubject<Bool, Never> { get }

    func ensureInitialized() async
    func initialize(serverUrl: String, apiKey: String) throws
    func testConnection() async -> Bool
    func getPreferences() -> SeerrPreferences?

    func getMovieDetails(tmdbId: Int) async throws -> SeerrMovieDetailsDto
    func getTvDetails(tmdbId: Int) async throws -> SeerrTvDetailsDto

    func loginWithJellyfin(username: String, password: String, jellyfinUrl: String, seerrUrl: String) async throws -> SeerrUserDto
    func loginLocal(email: String, password: String, seerrUrl: String) async throws -> SeerrUserDto
    func loginWithApiKey(apiKey: String, seerrUrl: String) async throws -> SeerrUserDto
    func regenerateApiKey() async throws -> String
    func isSessionValid() async -> Bool
    func isSessionValidCached() async -> Bool
    func getCurrentUser() async throws -> SeerrUserDto

    func getRequests(filter: String?, requestedBy: Int?, limit: Int, offset: Int) async throws -> SeerrListResponse<SeerrRequestDto>
    func createRequest(mediaId: Int, mediaType: String, seasons: SeerrSeasons?, is4k: Bool, profileId: Int?, rootFolderId: Int?, serverId: Int?) async throws -> SeerrRequestDto
    func deleteRequest(requestId: Int) async throws

    func getTrending(limit: Int, offset: Int) async throws -> SeerrDiscoverPageDto
    func getTrendingMovies(limit: Int, offset: Int) async throws -> SeerrDiscoverPageDto
    func getTrendingTv(limit: Int, offset: Int) async throws -> SeerrDiscoverPageDto
    func getTopMovies(limit: Int, offset: Int) async throws -> SeerrDiscoverPageDto
    func getTopTv(limit: Int, offset: Int) async throws -> SeerrDiscoverPageDto
    func getUpcomingMovies() async throws -> SeerrDiscoverPageDto
    func getUpcomingTv() async throws -> SeerrDiscoverPageDto
    func getRecentlyAdded(limit: Int) async throws -> SeerrListResponse<SeerrMediaDto>

    func search(query: String, mediaType: String?, limit: Int, offset: Int) async throws -> SeerrDiscoverPageDto
    func getSimilarMovies(tmdbId: Int, page: Int) async throws -> SeerrDiscoverPageDto
    func getSimilarTv(tmdbId: Int, page: Int) async throws -> SeerrDiscoverPageDto
    func getRecommendationsMovies(tmdbId: Int, page: Int) async throws -> SeerrDiscoverPageDto
    func getRecommendationsTv(tmdbId: Int, page: Int) async throws -> SeerrDiscoverPageDto
    func getPersonDetails(personId: Int) async throws -> SeerrPersonDetailsDto
    func getPersonCombinedCredits(personId: Int) async throws -> SeerrPersonCombinedCreditsDto
    func getGenreSliderMovies() async throws -> [SeerrGenreDto]
    func getGenreSliderTv() async throws -> [SeerrGenreDto]

    func discoverMovies(page: Int, sortBy: String, genre: Int?, studio: Int?, keywords: Int?, language: String) async throws -> SeerrDiscoverPageDto
    func discoverTv(page: Int, sortBy: String, genre: Int?, network: Int?, keywords: Int?, language: String) async throws -> SeerrDiscoverPageDto

    func getRadarrServers() async throws -> [SeerrServiceServerDto]
    func getRadarrServerDetails(serverId: Int) async throws -> SeerrServiceServerDetailsDto
    func getSonarrServers() async throws -> [SeerrServiceServerDto]
    func getSonarrServerDetails(serverId: Int) async throws -> SeerrServiceServerDetailsDto
    func getRadarrSettings() async throws -> [SeerrRadarrSettingsDto]
    func getSonarrSettings() async throws -> [SeerrSonarrSettingsDto]

    func configureWithMoonfin(jellyfinBaseUrl: String, jellyfinToken: String) async throws -> MoonfinStatusResponse
    func checkMoonfinStatus() async throws -> MoonfinStatusResponse
    func loginWithMoonfin(username: String, password: String, authType: String) async throws -> MoonfinLoginResponse
    func logoutMoonfin() async
    func logout() async

    func getJellyfinSessionInfo() -> (username: String, serverUrl: String)?
}

final class SeerrRepository: SeerrRepositoryProtocol {
    let isAvailable = CurrentValueSubject<Bool, Never>(false)
    let isMoonfinMode = CurrentValueSubject<Bool, Never>(false)

    private let userRepository: UserRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory
    private let sessionRepository: SessionRepositoryProtocol
    private let serverRepository: ServerRepositoryProtocol
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "SeerrRepository")

    private var httpClient: SeerrHttpClient?
    private var initialized = false
    private var lastUserId: String?

    private var lastSessionCheckTime: Date?
    private var lastSessionValid = false
    private static let sessionCacheDuration: TimeInterval = 300

    init(
        userRepository: UserRepositoryProtocol,
        serverClientFactory: MediaServerClientFactory,
        sessionRepository: SessionRepositoryProtocol,
        serverRepository: ServerRepositoryProtocol
    ) {
        self.userRepository = userRepository
        self.serverClientFactory = serverClientFactory
        self.sessionRepository = sessionRepository
        self.serverRepository = serverRepository
    }

    // MARK: - Preferences

    func getPreferences() -> SeerrPreferences? {
        guard let userId = userRepository.currentUser.value?.id else { return nil }
        return SeerrPreferences.forUser(userId)
    }

    // MARK: - Client Access

    private func withClient<T>(_ block: (SeerrHttpClient) async throws -> T) async throws -> T {
        await ensureInitialized()
        guard let client = httpClient else {
            throw SeerrRepositoryError.notInitialized
        }
        return try await block(client)
    }

    // MARK: - Initialization

    func initialize(serverUrl: String, apiKey: String) {
        httpClient = SeerrHttpClient(baseUrl: serverUrl, apiKey: apiKey)
        initialized = true
    }

    private func invalidateSessionCache() {
        lastSessionCheckTime = nil
        lastSessionValid = false
    }

    func ensureInitialized() async {
        let currentUserId = userRepository.currentUser.value?.id

        if initialized, let uid = currentUserId, uid != lastUserId {
            initialized = false
            httpClient = nil
            isAvailable.send(false)
            invalidateSessionCache()
        }

        if initialized && httpClient == nil {
            initialized = false
        }

        guard !initialized else { return }

        let prefs = getPreferences()
        let serverUrl = prefs?[SeerrPreferences.serverUrl] ?? ""
        let enabled = prefs?[SeerrPreferences.enabled] ?? false

        guard let user = userRepository.currentUser.value else {
            isAvailable.send(false)
            initialized = true
            return
        }

        SeerrHttpClient.switchCookieStorage(userId: user.id)
        lastUserId = user.id

        let storedApiKey = prefs?[SeerrPreferences.apiKey] ?? ""
        let authMethod = prefs?[SeerrPreferences.authMethod] ?? ""
        let moonfinMode = prefs?[SeerrPreferences.moonfinMode] ?? false

        if moonfinMode {
            await initializeMoonfinMode()
            initialized = true
            return
        }

        guard enabled, !serverUrl.isEmpty else {
            isAvailable.send(false)
            initialized = true
            return
        }

        if !storedApiKey.isEmpty {
            initialize(serverUrl: serverUrl, apiKey: storedApiKey)
            isAvailable.send(true)
        } else if authMethod == "jellyfin" || authMethod == "local" {
            initialize(serverUrl: serverUrl, apiKey: "")
            let valid = await isSessionValid()
            isAvailable.send(valid)
            if !valid {
                logger.warning("Session expired, user needs to re-authenticate")
            }
        } else {
            isAvailable.send(false)
        }

        initialized = true
    }

    private func initializeMoonfinMode() async {
        guard let session = sessionRepository.currentSession.value,
              let server = serverRepository.currentServer.value else {
            isAvailable.send(false)
            logger.warning("Moonfin mode enabled but no active session/server")
            return
        }

        let client = serverClientFactory.configuredClient(
            for: server, accessToken: session.accessToken, userId: session.userId.uuidString
        )

        guard let baseUrl = client.baseURL?.absoluteString,
              let token = client.accessToken,
              !baseUrl.isEmpty, !token.isEmpty else {
            isAvailable.send(false)
            logger.warning("Moonfin mode enabled but no Jellyfin API credentials")
            return
        }

        let proxyConfig = MoonfinProxyConfig(jellyfinBaseUrl: baseUrl, jellyfinToken: token)

        do {
            initialize(serverUrl: baseUrl, apiKey: "")
            httpClient?.proxyConfig = proxyConfig
            isMoonfinMode.send(true)

            let status = try await httpClient?.getMoonfinStatus()
            if status?.authenticated == true {
                isAvailable.send(true)
            } else {
                isAvailable.send(false)
            }
        } catch {
            isAvailable.send(false)
            logger.warning("Failed to initialize for Moonfin proxy")
        }
    }

    // MARK: - Connection

    func testConnection() async -> Bool {
        do {
            return try await withClient { try await $0.testConnection() }
        } catch {
            return false
        }
    }

    func getJellyfinSessionInfo() -> (username: String, serverUrl: String)? {
        guard let user = userRepository.currentUser.value,
              let server = serverRepository.currentServer.value else { return nil }
        return (username: user.name, serverUrl: server.address)
    }

    // MARK: - Session Validation

    func isSessionValid() async -> Bool {
        do {
            _ = try await withClient { try await $0.getCurrentUser() }
            return true
        } catch {
            return false
        }
    }

    func isSessionValidCached() async -> Bool {
        if let lastCheck = lastSessionCheckTime,
           Date().timeIntervalSince(lastCheck) < Self.sessionCacheDuration,
           lastSessionValid {
            return true
        }
        let valid = await isSessionValid()
        lastSessionCheckTime = Date()
        lastSessionValid = valid
        return valid
    }

    func getCurrentUser() async throws -> SeerrUserDto {
        try await withClient { try await $0.getCurrentUser() }
    }

    // MARK: - Auth: Jellyfin

    func loginWithJellyfin(username: String, password: String, jellyfinUrl: String, seerrUrl: String) async throws -> SeerrUserDto {
        guard let userId = userRepository.currentUser.value?.id else {
            throw SeerrRepositoryError.noActiveUser
        }

        SeerrHttpClient.switchCookieStorage(userId: userId)
        let prefs = getPreferences()
        prefs?[SeerrPreferences.authMethod] = "jellyfin"
        prefs?[SeerrPreferences.serverUrl] = seerrUrl

        initialize(serverUrl: seerrUrl, apiKey: "")

        let user = try await httpClient!.loginJellyfin(username: username, password: password, jellyfinUrl: jellyfinUrl)
        prefs?[SeerrPreferences.enabled] = true
        prefs?[SeerrPreferences.lastConnectionSuccess] = true
        isAvailable.send(true)

        if prefs?[SeerrPreferences.autoGenerateApiKey] == true {
            if let apiKey = try? await httpClient?.regenerateApiKey() {
                prefs?[SeerrPreferences.apiKey] = apiKey
                prefs?[SeerrPreferences.authMethod] = "jellyfin-apikey"
            }
        }

        return user
    }

    // MARK: - Auth: Local

    func loginLocal(email: String, password: String, seerrUrl: String) async throws -> SeerrUserDto {
        guard let userId = userRepository.currentUser.value?.id else {
            throw SeerrRepositoryError.noActiveUser
        }

        SeerrHttpClient.switchCookieStorage(userId: userId)
        let prefs = getPreferences()
        prefs?[SeerrPreferences.authMethod] = "local"
        prefs?[SeerrPreferences.localEmail] = email
        prefs?[SeerrPreferences.localPassword] = password
        prefs?[SeerrPreferences.serverUrl] = seerrUrl

        initialize(serverUrl: seerrUrl, apiKey: "")

        let user = try await httpClient!.loginLocal(email: email, password: password)
        prefs?[SeerrPreferences.enabled] = true
        prefs?[SeerrPreferences.lastConnectionSuccess] = true
        isAvailable.send(true)

        if prefs?[SeerrPreferences.autoGenerateApiKey] == true {
            if let apiKey = try? await httpClient?.regenerateApiKey() {
                prefs?[SeerrPreferences.apiKey] = apiKey
                prefs?[SeerrPreferences.authMethod] = "local-apikey"
            }
        }

        return user
    }

    // MARK: - Auth: API Key

    func loginWithApiKey(apiKey: String, seerrUrl: String) async throws -> SeerrUserDto {
        guard let userId = userRepository.currentUser.value?.id else {
            throw SeerrRepositoryError.noActiveUser
        }

        SeerrHttpClient.switchCookieStorage(userId: userId)
        let prefs = getPreferences()
        prefs?[SeerrPreferences.authMethod] = "apikey"
        prefs?[SeerrPreferences.apiKey] = apiKey
        prefs?[SeerrPreferences.serverUrl] = seerrUrl

        initialize(serverUrl: seerrUrl, apiKey: apiKey)

        let user = try await httpClient!.getCurrentUser()
        prefs?[SeerrPreferences.enabled] = true
        prefs?[SeerrPreferences.lastConnectionSuccess] = true
        isAvailable.send(true)

        return user
    }

    // MARK: - Auth: Regenerate API Key

    func regenerateApiKey() async throws -> String {
        let apiKey = try await withClient { try await $0.regenerateApiKey() }
        let prefs = getPreferences()
        prefs?[SeerrPreferences.apiKey] = apiKey
        prefs?[SeerrPreferences.authMethod] = "jellyfin-apikey"
        return apiKey
    }

    // MARK: - Media Details

    func getMovieDetails(tmdbId: Int) async throws -> SeerrMovieDetailsDto {
        try await withClient { try await $0.getMovieDetails(tmdbId: tmdbId) }
    }

    func getTvDetails(tmdbId: Int) async throws -> SeerrTvDetailsDto {
        try await withClient { try await $0.getTvDetails(tmdbId: tmdbId) }
    }

    // MARK: - Requests

    func getRequests(filter: String? = nil, requestedBy: Int? = nil, limit: Int = 50, offset: Int = 0) async throws -> SeerrListResponse<SeerrRequestDto> {
        try await withClient { try await $0.getRequests(filter: filter, requestedBy: requestedBy, limit: limit, offset: offset) }
    }

    func createRequest(mediaId: Int, mediaType: String, seasons: SeerrSeasons? = nil, is4k: Bool = false, profileId: Int? = nil, rootFolderId: Int? = nil, serverId: Int? = nil) async throws -> SeerrRequestDto {
        try await withClient { try await $0.createRequest(mediaId: mediaId, mediaType: mediaType, seasons: seasons, is4k: is4k, profileId: profileId, rootFolderId: rootFolderId, serverId: serverId) }
    }

    func deleteRequest(requestId: Int) async throws {
        try await withClient { try await $0.deleteRequest(requestId: requestId) }
    }

    // MARK: - Discovery

    func getTrending(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getTrending(limit: limit, offset: offset) }
    }

    func getTrendingMovies(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getTrendingMovies(limit: limit, offset: offset) }
    }

    func getTrendingTv(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getTrendingTv(limit: limit, offset: offset) }
    }

    func getTopMovies(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getTopMovies(limit: limit, offset: offset) }
    }

    func getTopTv(limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getTopTv(limit: limit, offset: offset) }
    }

    func getUpcomingMovies() async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getUpcomingMovies() }
    }

    func getUpcomingTv() async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getUpcomingTv() }
    }

    func getRecentlyAdded(limit: Int = 20) async throws -> SeerrListResponse<SeerrMediaDto> {
        try await withClient { try await $0.getRecentlyAdded(limit: limit) }
    }

    // MARK: - Search

    func search(query: String, mediaType: String? = nil, limit: Int = 20, offset: Int = 0) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.search(query: query, mediaType: mediaType, limit: limit, offset: offset) }
    }

    // MARK: - Similar & Recommendations

    func getSimilarMovies(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getSimilarMovies(tmdbId: tmdbId, page: page) }
    }

    func getSimilarTv(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getSimilarTv(tmdbId: tmdbId, page: page) }
    }

    func getRecommendationsMovies(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getRecommendationsMovies(tmdbId: tmdbId, page: page) }
    }

    func getRecommendationsTv(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.getRecommendationsTv(tmdbId: tmdbId, page: page) }
    }

    // MARK: - Person

    func getPersonDetails(personId: Int) async throws -> SeerrPersonDetailsDto {
        try await withClient { try await $0.getPersonDetails(personId: personId) }
    }

    func getPersonCombinedCredits(personId: Int) async throws -> SeerrPersonCombinedCreditsDto {
        try await withClient { try await $0.getPersonCombinedCredits(personId: personId) }
    }

    // MARK: - Genre Sliders

    func getGenreSliderMovies() async throws -> [SeerrGenreDto] {
        try await withClient { try await $0.getGenreSliderMovies() }
    }

    func getGenreSliderTv() async throws -> [SeerrGenreDto] {
        try await withClient { try await $0.getGenreSliderTv() }
    }

    // MARK: - Discover with Filters

    func discoverMovies(page: Int = 1, sortBy: String = "popularity.desc", genre: Int? = nil, studio: Int? = nil, keywords: Int? = nil, language: String = "en") async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.discoverMovies(page: page, sortBy: sortBy, genre: genre, studio: studio, keywords: keywords, language: language) }
    }

    func discoverTv(page: Int = 1, sortBy: String = "popularity.desc", genre: Int? = nil, network: Int? = nil, keywords: Int? = nil, language: String = "en") async throws -> SeerrDiscoverPageDto {
        try await withClient { try await $0.discoverTv(page: page, sortBy: sortBy, genre: genre, network: network, keywords: keywords, language: language) }
    }

    // MARK: - Service Configuration

    func getRadarrServers() async throws -> [SeerrServiceServerDto] {
        try await withClient { try await $0.getRadarrServers() }
    }

    func getRadarrServerDetails(serverId: Int) async throws -> SeerrServiceServerDetailsDto {
        try await withClient { try await $0.getRadarrServerDetails(serverId: serverId) }
    }

    func getSonarrServers() async throws -> [SeerrServiceServerDto] {
        try await withClient { try await $0.getSonarrServers() }
    }

    func getSonarrServerDetails(serverId: Int) async throws -> SeerrServiceServerDetailsDto {
        try await withClient { try await $0.getSonarrServerDetails(serverId: serverId) }
    }

    func getRadarrSettings() async throws -> [SeerrRadarrSettingsDto] {
        try await withClient { try await $0.getRadarrSettings() }
    }

    func getSonarrSettings() async throws -> [SeerrSonarrSettingsDto] {
        try await withClient { try await $0.getSonarrSettings() }
    }

    // MARK: - Moonfin Proxy

    func configureWithMoonfin(jellyfinBaseUrl: String, jellyfinToken: String) async throws -> MoonfinStatusResponse {
        guard let userId = userRepository.currentUser.value?.id else {
            throw SeerrRepositoryError.noActiveUser
        }

        SeerrHttpClient.switchCookieStorage(userId: userId)
        lastUserId = userId

        let proxyConfig = MoonfinProxyConfig(jellyfinBaseUrl: jellyfinBaseUrl, jellyfinToken: jellyfinToken)
        initialize(serverUrl: jellyfinBaseUrl, apiKey: "")
        httpClient?.proxyConfig = proxyConfig

        let status = try await httpClient!.getMoonfinStatus()
        let prefs = getPreferences()
        prefs?[SeerrPreferences.moonfinMode] = true
        prefs?[SeerrPreferences.enabled] = true
        prefs?[SeerrPreferences.authMethod] = "moonfin"
        isMoonfinMode.send(true)

        if status.authenticated {
            if let seerrUserId = status.jellyseerrUserId {
                prefs?[SeerrPreferences.moonfinJellyseerrUserId] = String(seerrUserId)
            }
            isAvailable.send(true)
        } else {
            isAvailable.send(false)
        }

        return status
    }

    func checkMoonfinStatus() async throws -> MoonfinStatusResponse {
        try await withClient { try await $0.getMoonfinStatus() }
    }

    func loginWithMoonfin(username: String, password: String, authType: String = "jellyfin") async throws -> MoonfinLoginResponse {
        await ensureInitialized()
        guard let client = httpClient, client.isProxyMode else {
            throw SeerrRepositoryError.notInMoonfinMode
        }

        let response = try await client.moonfinLogin(username: username, password: password, authType: authType)
        if response.success {
            let prefs = getPreferences()
            prefs?[SeerrPreferences.moonfinDisplayName] = response.displayName ?? ""
            if let seerrUserId = response.jellyseerrUserId {
                prefs?[SeerrPreferences.moonfinJellyseerrUserId] = String(seerrUserId)
            }
            isAvailable.send(true)
        }

        return response
    }

    func logoutMoonfin() async {
        if let client = httpClient, client.isProxyMode {
            try? await client.moonfinLogout()
        }

        let prefs = getPreferences()
        prefs?[SeerrPreferences.moonfinMode] = false
        prefs?[SeerrPreferences.moonfinDisplayName] = ""
        prefs?[SeerrPreferences.moonfinJellyseerrUserId] = ""
        prefs?[SeerrPreferences.enabled] = false
        prefs?[SeerrPreferences.authMethod] = ""

        httpClient?.proxyConfig = nil
        isMoonfinMode.send(false)
        isAvailable.send(false)
        initialized = false
    }

    func logout() async {
        if httpClient?.isProxyMode == true {
            await logoutMoonfin()
            return
        }

        let prefs = getPreferences()
        prefs?[SeerrPreferences.serverUrl] = ""
        prefs?[SeerrPreferences.enabled] = false
        prefs?[SeerrPreferences.localEmail] = ""
        prefs?[SeerrPreferences.localPassword] = ""
        prefs?[SeerrPreferences.apiKey] = ""
        prefs?[SeerrPreferences.authMethod] = ""

        httpClient = nil
        initialized = false
        lastUserId = nil
        isAvailable.send(false)
    }
}

enum SeerrRepositoryError: LocalizedError {
    case notInitialized
    case noActiveUser
    case notInMoonfinMode

    private static func l(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    var errorDescription: String? {
        switch self {
        case .notInitialized: return Self.l("seerr_http_client_not_initialized")
        case .noActiveUser: return Self.l("seerr_no_active_jellyfin_user")
        case .notInMoonfinMode: return Self.l("seerr_not_in_moonfin_proxy_mode")
        }
    }
}
