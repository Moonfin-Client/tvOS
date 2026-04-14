import SwiftUI
import Combine
import JavaScriptCore
import UIKit

@MainActor
final class AppContainer: ObservableObject {

    // MARK: - Core

    let deviceInfo: DeviceInfo

    // MARK: - Stores

    let preferenceStore: PreferenceStore
    let keychainStore: KeychainStore
    let authenticationStore: AuthenticationStore

    // MARK: - Preferences

    let authPreferences: AuthenticationPreferences
    let userPreferences: UserPreferences
    let telemetryPreferences: TelemetryPreferences
    let localizationPreferences: LocalizationPreferences

    // MARK: - Server

    let serverClientFactory: MediaServerClientFactory

    // MARK: - Services

    let dataRefreshService: DataRefreshService
    let pluginSyncService: PluginSyncService
    let itemMutationService: ItemMutationService
    let spotlightIndexer: SpotlightIndexer
    let inactivityTracker: InactivityTracker
    private var inactivityTrackerCancellable: AnyCancellable?
    private var appForegroundCancellable: AnyCancellable?
    private var appBackgroundCancellable: AnyCancellable?
    let serverConnectionMonitor: ServerConnectionMonitor
    let featureDegradationManager: FeatureDegradationManager
    let userViewsService: UserViewsService

    // MARK: - Playback

    let playbackCoordinator: PlaybackCoordinator

    // MARK: - SyncPlay

    let syncPlayManager: SyncPlayManager
    let syncPlayRuntimeCoordinator: SyncPlayRuntimeCoordinator

    // MARK: - Repositories

    let userRepository: UserRepositoryProtocol
    let serverRepository: ServerRepositoryProtocol
    let sessionRepository: SessionRepositoryProtocol
    let serverUserRepository: ServerUserRepositoryProtocol
    let authenticationRepository: AuthenticationRepositoryProtocol
    let mdbListRepository: MdbListRepository
    let tmdbRepository: TmdbRepository
    let seerrRepository: SeerrRepositoryProtocol
    let multiServerRepository: MultiServerRepositoryProtocol
    let parentalControlsRepository: ParentalControlsRepository

    init(
        preferenceStore: PreferenceStore? = nil,
        keychainStore: KeychainStore? = nil,
        authenticationStore: AuthenticationStore? = nil,
        serverClientFactory: MediaServerClientFactory? = nil
    ) {
        let store = preferenceStore ?? UserDefaultsPreferenceStore()
        let authStore = authenticationStore ?? AuthenticationStore()
        let factory = serverClientFactory ?? MediaServerClientFactory()
        let authPrefs = AuthenticationPreferences(store: store)

        self.deviceInfo = DeviceInfo()
        self.preferenceStore = store
        self.keychainStore = keychainStore ?? KeychainStore()
        self.authenticationStore = authStore
        self.authPreferences = authPrefs
        self.userPreferences = UserPreferences(store: store)
        self.telemetryPreferences = TelemetryPreferences(store: store)
        self.localizationPreferences = LocalizationPreferences(store: store)
        self.serverClientFactory = factory
        self.dataRefreshService = DataRefreshService()

        let userRepo = UserRepository()
        let serverRepo = ServerRepository(authenticationStore: authStore, serverClientFactory: factory)
        let sessionRepo = SessionRepository(
            authPreferences: authPrefs,
            authenticationStore: authStore,
            serverClientFactory: factory,
            userRepository: userRepo,
            serverRepository: serverRepo
        )
        let serverUserRepo = ServerUserRepository(authenticationStore: authStore, serverClientFactory: factory)
        let authRepo = AuthenticationRepository(
            authenticationStore: authStore,
            authPreferences: authPrefs,
            serverClientFactory: factory,
            sessionRepository: sessionRepo
        )

        self.userRepository = userRepo
        self.serverRepository = serverRepo
        self.sessionRepository = sessionRepo
        self.serverUserRepository = serverUserRepo
        self.authenticationRepository = authRepo
        self.itemMutationService = ItemMutationService(serverClientFactory: factory, serverRepository: serverRepo)
        self.spotlightIndexer = SpotlightIndexer(serverClientFactory: factory, serverRepository: serverRepo)
        self.playbackCoordinator = PlaybackCoordinator(
            serverClientFactory: factory,
            serverRepository: serverRepo,
            preferences: self.userPreferences,
            dataRefreshService: self.dataRefreshService
        )
        self.inactivityTracker = InactivityTracker(
            userPreferences: self.userPreferences,
            playbackCoordinator: self.playbackCoordinator
        )
        self.syncPlayManager = SyncPlayManager(
            serverRepository: serverRepo,
            serverClientFactory: factory,
            playbackCoordinator: self.playbackCoordinator,
            userPreferences: self.userPreferences
        )
        let coordinator = SyncPlayRuntimeCoordinator(
            serverRepository: serverRepo,
            serverClientFactory: factory,
            syncPlayManager: self.syncPlayManager
        )
        self.syncPlayRuntimeCoordinator = coordinator

        self.serverConnectionMonitor = ServerConnectionMonitor(
            serverClientFactory: factory,
            serverRepository: serverRepo
        )
        self.featureDegradationManager = FeatureDegradationManager()
        self.userViewsService = UserViewsService(
            serverRepository: serverRepo,
            serverClientFactory: factory,
            userRepository: userRepo,
            userPreferences: self.userPreferences
        )

        let resolveClient: () -> HttpClient? = { [weak serverRepo] in
            guard let server = serverRepo?.currentServer.value else { return nil }
            return factory.client(for: server).httpClient
        }

        self.mdbListRepository = MdbListRepository(resolveClient: resolveClient)
        self.tmdbRepository = TmdbRepository(resolveClient: resolveClient)
        self.seerrRepository = SeerrRepository(
            userRepository: userRepo,
            serverClientFactory: factory,
            sessionRepository: sessionRepo,
            serverRepository: serverRepo
        )
        self.multiServerRepository = MultiServerRepository(
            serverRepository: serverRepo,
            sessionRepository: sessionRepo,
            authenticationStore: authStore,
            serverClientFactory: factory
        )
        self.parentalControlsRepository = ParentalControlsRepository(
            sessionRepository: sessionRepo,
            multiServerRepository: self.multiServerRepository
        )

        let seerrRepo = self.seerrRepository
        let parentalRepo = self.parentalControlsRepository
        self.pluginSyncService = PluginSyncService(
            resolveClient: resolveClient,
            resolveSeerrRepository: { [weak seerrRepo] in seerrRepo },
            resolveParentalRepository: { [weak parentalRepo] in parentalRepo }
        )

        CrashReporter.shared.configure(preferences: self.telemetryPreferences)
        LocalizationManager.shared.configure(preferences: self.localizationPreferences)

        self.inactivityTrackerCancellable = self.inactivityTracker.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }

        self.appForegroundCancellable = NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.syncPlayRuntimeCoordinator.appDidBecomeActive()
                self?.syncPlayManager.appDidBecomeActive()
            }

        self.appBackgroundCancellable = NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.syncPlayManager.appDidEnterBackground()
                self?.syncPlayRuntimeCoordinator.appDidEnterBackground()
            }

        coordinator.start()
    }
}

enum TrailerPlaybackHelper {
    static func firstYouTubeVideoId(from trailers: [MediaUrl]?) -> String? {
        trailers?.lazy
            .compactMap { $0.url }
            .compactMap(extractYouTubeVideoId)
            .first
    }

    static func extractYouTubeVideoId(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        guard let host = url.host?.lowercased() else { return nil }

        if host.contains("youtu.be") {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }

        if host.contains("youtube.com") {
            if let queryId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value,
               !queryId.isEmpty {
                return queryId
            }

            let pathComponents = url.path.split(separator: "/")
            if pathComponents.count >= 2,
               (pathComponents[0] == "embed" || pathComponents[0] == "shorts") {
                let id = String(pathComponents[1])
                return id.isEmpty ? nil : id
            }
        }

        return nil
    }

    @MainActor
    static func playTrailer(
        for item: ServerItem,
        client: MediaServerClient,
        playbackCoordinator: PlaybackCoordinator,
        router: NavigationRouter
    ) async -> Bool {
        do {
            let trailers = try await client.userLibraryApi.getLocalTrailers(itemId: item.id)
            if !trailers.isEmpty {
                await playbackCoordinator.startVideoPlayback(items: trailers)
                router.navigate(to: .videoPlayer)
                return true
            }
        } catch { }

        if let videoId = firstYouTubeVideoId(from: item.remoteTrailers) {
            router.navigate(to: .trailerPlayer(videoId: videoId))
            return true
        }

        return false
    }
}

// MARK: - YouTube Stream Resolver

/// Resolves direct playable stream URLs from YouTube video IDs.
/// Uses JavaScriptCore for signature cipher & n-parameter descrambling
/// (the same approach as NewPipe Extractor on Android, but in Swift).
enum YouTubeStreamResolver {

    struct StreamInfo {
        let url: URL
        let isHLS: Bool
    }

    /// Desktop Firefox UA matching Android's NewPipeDownloader
    private static let browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
    private static let trustedFallbackPlayerPath = "/s/player/0004de42/player_ias.vflset/en_US/base.js"

    /// Diagnostic log lines collected during resolution (surfaced in error UI)
    private static var _diagnostics: [String] = []
    private static var _trustedFallbackPlayerJS: String?
    private static func log(_ msg: String) { _diagnostics.append(msg) }

    struct ResolveResult {
        let stream: StreamInfo?
        let diagnostics: String
    }

    enum ResolveMode {
        case full
        case preview
    }

    static func resolveStream(videoId: String, mode: ResolveMode = .full, minHeight: Int = 1080) async -> ResolveResult {
        _diagnostics = []
        log("Resolving videoId: \(videoId)")
        var bestEffortStream: StreamInfo?

        if mode == .full {
            log("[Resolver] API-first mode: trying Piped/Invidious before direct YouTube extraction")

            if let stream = await resolveViaPiped(videoId: videoId) {
                if await validatePlayableStream(stream) {
                    log(" Piped strategy succeeded")
                    return ResolveResult(stream: stream, diagnostics: _diagnostics.joined(separator: "\n"))
                }
                log("[Validate] Piped stream failed preflight, trying next strategy")
                if bestEffortStream == nil { bestEffortStream = stream }
            }

            if let stream = await resolveViaInvidious(videoId: videoId) {
                if await validatePlayableStream(stream) {
                    log(" Invidious strategy succeeded")
                    return ResolveResult(stream: stream, diagnostics: _diagnostics.joined(separator: "\n"))
                }
                log("[Validate] Invidious stream failed preflight, trying next strategy")
                if bestEffortStream == nil { bestEffortStream = stream }
            }
        }

        let pageData = await fetchWatchPage(videoId: videoId)
        let playerJS: String?
        if let html = pageData?.html {
            log("[Page] \u{2713} Got HTML (\(html.count) chars)")
            playerJS = await fetchPlayerJS(from: html)
            log("[Page] player.js: \(playerJS != nil ? "\u{2713} (\(playerJS!.count) chars)" : "\u{2717} not found")")
            if _trustedFallbackPlayerJS == nil {
                _trustedFallbackPlayerJS = await fetchPlayerJS(fromPath: trustedFallbackPlayerPath)
                log("[Page] trusted n-player: \(_trustedFallbackPlayerJS != nil ? "\u{2713} (\(_trustedFallbackPlayerJS!.count) chars)" : "\u{2717} not found")")
            }
        } else {
            log("[Page] \u{2717} Failed to fetch page HTML")
            playerJS = nil
        }

        if let html = pageData?.html,
           let stream = extractStreamsFromPage(html: html, playerJS: playerJS, minHeight: minHeight) {
            if await validatePlayableStream(stream) {
                log("\u{2713} Page extraction strategy succeeded")
                return ResolveResult(stream: stream, diagnostics: _diagnostics.joined(separator: "\n"))
            }
            log("[Validate] Page extraction stream failed preflight, trying next strategy")
            if bestEffortStream == nil || !bestEffortStream!.isHLS {
                bestEffortStream = stream
            }
        }

        if let stream = await resolveViaInnertube(videoId: videoId, playerJS: playerJS, minHeight: minHeight) {
            if await validatePlayableStream(stream) {
                log("\u{2713} Innertube strategy succeeded")
                return ResolveResult(stream: stream, diagnostics: _diagnostics.joined(separator: "\n"))
            }
            log("[Validate] Innertube stream failed preflight, trying next strategy")
            if bestEffortStream == nil { bestEffortStream = stream }
        }

        if let bestEffortStream {
            log("[Resolver]  Returning best-effort \(bestEffortStream.isHLS ? "HLS" : "muxed") stream despite failed preflight")
            return ResolveResult(stream: bestEffortStream, diagnostics: _diagnostics.joined(separator: "\n"))
        }

        log("\u{2717} All strategies failed")
        return ResolveResult(stream: nil, diagnostics: _diagnostics.joined(separator: "\n"))
    }

    private static func validatePlayableStream(_ stream: StreamInfo) async -> Bool {
        if stream.isHLS {
            return await validateHLSStream(stream.url)
        }

        var request = URLRequest(url: stream.url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log("[Validate] \u{2717} Non-HTTP response")
                return false
            }

            if (200...206).contains(http.statusCode) || http.statusCode == 301 || http.statusCode == 302 {
                log("[Validate] \u{2713} HTTP \(http.statusCode) from \(stream.url.host ?? "unknown")")
                return true
            }

            if http.statusCode == 405 {
                return await validateViaGetProbe(stream)
            }

            log("[Validate] \u{2717} HTTP \(http.statusCode) from \(stream.url.host ?? "unknown")")
            return false
        } catch {
            log("[Validate] \u{2717} Request failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func validateHLSStream(_ manifestURL: URL, depth: Int = 0) async -> Bool {
        guard depth <= 2 else {
            log("[Validate] HLS playlist nesting too deep")
            return false
        }

        var request = URLRequest(url: manifestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("application/x-mpegURL, application/vnd.apple.mpegurl, */*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log("[Validate] HLS manifest non-HTTP response")
                return false
            }

            guard (200...299).contains(http.statusCode),
                  let body = String(data: data, encoding: .utf8) else {
                log("[Validate] HLS manifest HTTP \(http.statusCode) from \(manifestURL.host ?? "unknown")")
                return false
            }

            let entries = body
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }

            guard let firstEntry = entries.first,
                  let firstURL = URL(string: firstEntry, relativeTo: manifestURL)?.absoluteURL else {
                log("[Validate] HLS manifest has no playable entries")
                return false
            }

            if looksLikeHLSManifest(firstEntry) {
                return await validateHLSStream(firstURL, depth: depth + 1)
            }

            let ok = await validateDirectMediaURL(firstURL)
            log("[Validate] HLS segment probe \(ok ? "OK" : "FAILED") from \(firstURL.host ?? "unknown")")
            return ok
        } catch {
            log("[Validate] HLS manifest request failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func looksLikeHLSManifest(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains(".m3u8") || lower.contains("format=m3u8")
    }

    private static func validateDirectMediaURL(_ url: URL) async -> Bool {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 8
        head.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        head.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        head.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        head.setValue("*/*", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: head)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200...206).contains(http.statusCode) || http.statusCode == 301 || http.statusCode == 302 {
                return true
            }
            if http.statusCode == 405 {
                return await validateViaGetProbe(StreamInfo(url: url, isHLS: false))
            }
            return false
        } catch {
            return false
        }
    }

    private static func validateViaGetProbe(_ stream: StreamInfo) async -> Bool {
        var request = URLRequest(url: stream.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let ok = (200...206).contains(http.statusCode)
            log("[Validate] GET probe HTTP \(http.statusCode) from \(stream.url.host ?? "unknown") → \(ok ? "" : "")")
            return ok
        } catch {
            return false
        }
    }

    // MARK: - Strategy 1: Extract streams from page HTML

    private static func extractStreamsFromPage(html: String, playerJS: String?, minHeight: Int) -> StreamInfo? {
        guard let playerResponse = extractPlayerResponse(from: html) else {
            log("[PageExtract] \u{2717} No player response in HTML")
            return nil
        }
        log("[PageExtract] \u{2713} Extracted player response")
        return extractStreamFromPlayerResponse(playerResponse, playerJS: playerJS, label: "PageExtract", minHeight: minHeight)
    }

    private static func extractStreamFromPlayerResponse(
        _ playerResponse: [String: Any],
        playerJS: String?,
        label: String,
        minHeight: Int
    ) -> StreamInfo? {
        if let playability = playerResponse["playabilityStatus"] as? [String: Any] {
            let status = playability["status"] as? String ?? "unknown"
            let reason = playability["reason"] as? String
            log("[\(label)] Playability: \(status)\(reason.map { " \u{2014} \($0)" } ?? "")")
            if status != "OK" { return nil }
        }

        guard let streamingData = playerResponse["streamingData"] as? [String: Any] else {
            log("[\(label)] \u{2717} No streamingData")
            return nil
        }

        if let hlsUrl = streamingData["hlsManifestUrl"] as? String, let url = URL(string: hlsUrl) {
            log("[\(label)] \u{2713} HLS manifest")
            return StreamInfo(url: url, isHLS: true)
        }

        let muxedFormats = streamingData["formats"] as? [[String: Any]] ?? []
        let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] ?? []
        let cipherCount = (muxedFormats + adaptiveFormats).filter { $0["signatureCipher"] as? String != nil || $0["cipher"] as? String != nil }.count
        let directCount = (muxedFormats + adaptiveFormats).filter { $0["url"] as? String != nil }.count
        log("[\(label)] Formats: \(muxedFormats.count) muxed, \(adaptiveFormats.count) adaptive (\(directCount) direct, \(cipherCount) cipher)")

        if let stream = pickBestResolvedStream(from: muxedFormats, playerJS: playerJS, mimeFilter: nil, minPreferredHeight: minHeight) {
            log("[\(label)] \u{2713} Resolved muxed stream")
            return stream
        }
        if let stream = pickBestResolvedStream(from: adaptiveFormats, playerJS: playerJS, mimeFilter: "video/", minPreferredHeight: minHeight) {
            log("[\(label)] \u{2713} Resolved adaptive stream")
            return stream
        }

        log("[\(label)] \u{2717} Could not resolve any format")
        return nil
    }

    // MARK: - Strategy 2: Innertube API

    private static func resolveViaInnertube(videoId: String, playerJS: String?, minHeight: Int) async -> StreamInfo? {
        log("[Innertube] Trying API clients...")

        struct Client {
            let name: String
            let nameId: String
            let version: String
            let userAgent: String
            let apiKey: String
            let platform: String
            let extra: [String: Any]
            let embedContext: Bool
        }

        let clients = [
            Client(
                name: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
                nameId: "85",
                version: "2.0",
                userAgent: "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/6.0 TV Safari/538.1",
                apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
                platform: "TV",
                extra: [:],
                embedContext: true
            ),
            Client(
                name: "ANDROID",
                nameId: "3",
                version: "20.10.41",
                userAgent: "com.google.android.youtube/20.10.41 (Linux; U; Android 11) gzip",
                apiKey: "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w",
                platform: "MOBILE",
                extra: ["deviceMake": "Google", "deviceModel": "Pixel 5", "osName": "Android", "osVersion": "11", "androidSdkVersion": "30"],
                embedContext: false
            ),
            Client(
                name: "IOS",
                nameId: "5",
                version: "20.10.4",
                userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
                apiKey: "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc",
                platform: "MOBILE",
                extra: ["deviceMake": "Apple", "deviceModel": "iPhone16,2", "osName": "iOS", "osVersion": "18.3.2.22D82"],
                embedContext: false
            ),
            Client(
                name: "WEB",
                nameId: "1",
                version: "2.20250312.04.00",
                userAgent: browserUA,
                apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
                platform: "DESKTOP",
                extra: [:],
                embedContext: false
            ),
        ]

        for client in clients {
            log("[Innertube] Trying \(client.name)...")

            guard let apiURL = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(client.apiKey)&prettyPrint=false") else { continue }

            var clientContext: [String: Any] = [
                "clientName": client.name,
                "clientVersion": client.version,
                "hl": "en",
                "gl": "US",
                "platform": client.platform,
            ]
            for (k, v) in client.extra { clientContext[k] = v }

            var context: [String: Any] = ["client": clientContext]
            if client.embedContext {
                context["thirdParty"] = ["embedUrl": "https://www.youtube.com/"]
            }

            let body: [String: Any] = [
                "videoId": videoId,
                "context": context,
                "contentCheckOk": true,
                "racyCheckOk": true,
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { continue }

            var request = URLRequest(url: apiURL)
            request.httpMethod = "POST"
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
            request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
            request.setValue(client.nameId, forHTTPHeaderField: "X-YouTube-Client-Name")
            request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
            request.timeoutInterval = 10

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    log("[Innertube] \(client.name): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    continue
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    log("[Innertube] \(client.name): invalid JSON")
                    continue
                }
                if let stream = extractStreamFromPlayerResponse(json, playerJS: playerJS, label: "Innertube/\(client.name)", minHeight: minHeight) {
                    return stream
                }
            } catch {
                log("[Innertube] \(client.name): \(error.localizedDescription)")
            }
        }

        log("[Innertube] \u{2717} No client returned streams")
        return nil
    }

    private struct WatchPageData {
        let html: String
    }

    private static func fetchWatchPage(videoId: String) async -> WatchPageData? {
        // Try watch page first (more likely to have streamingData), then embed page
        let urls = [
            "https://www.youtube.com/watch?v=\(videoId)&bpctr=9999999999&has_verified=1",
            "https://www.youtube.com/embed/\(videoId)",
        ]

        for urlStr in urls {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
            request.setValue("CONSENT=PENDING+987; SOCS=CAESEwgDEgk2ODE3MTQxMjQaAmVuIAEaBgiA_LyaBg", forHTTPHeaderField: "Cookie")
            request.timeoutInterval = 12

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                guard let html = String(data: data, encoding: .utf8) else { continue }
                if html.contains("ytInitialPlayerResponse") || html.contains("embedded_player_response") || html.contains("streamingData") {
                    return WatchPageData(html: html)
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func extractPlayerResponse(from html: String) -> [String: Any]? {
        // Pattern 1: ytInitialPlayerResponse = {...};
        for pattern in ["ytInitialPlayerResponse\\s*=\\s*", "var ytInitialPlayerResponse\\s*=\\s*"] {
            if let json = extractJSONViaRegex(from: html, pattern: pattern) {
                return json
            }
        }

        // Pattern 2: embedded_player_response (escaped JSON in embed page)
        for prefix in ["\"embedded_player_response\":\"", "\"PLAYER_VARS\":{\"embedded_player_response\":\""] {
            if let range = html.range(of: prefix) {
                let rest = String(html[range.upperBound...])
                if let json = extractEscapedJSON(from: rest) {
                    return json
                }
            }
        }

        return nil
    }

    // MARK: Player.js Fetching & Cipher Extraction

    /// Extract the player.js URL from the HTML and download its source.
    private static func fetchPlayerJS(from html: String) async -> String? {
        // Find player.js URL: typically /s/player/<hash>/player_ias.vflset/en_US/base.js
        guard let regex = try? NSRegularExpression(pattern: "/s/player/[a-zA-Z0-9]+/[^\"]+\\.js", options: []),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else { return nil }

        return await fetchPlayerJS(fromPath: String(html[range]))
    }

    private static func fetchPlayerJS(fromPath playerPath: String) async -> String? {
        guard let playerURL = URL(string: "https://www.youtube.com\(playerPath)") else { return nil }

        var request = URLRequest(url: playerURL)
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Resolve a stream URL by descrambling signatureCipher and n-parameter using JavaScriptCore.
    private static func resolveStreamURL(from format: [String: Any], playerJS: String?) -> URL? {
        let itag = format["itag"] as? Int ?? -1

        // Case 1: direct URL
        if let urlStr = format["url"] as? String, let url = URL(string: urlStr) {
            log("[Resolve] itag \(itag): direct URL")
            // Apply n-parameter transform - without it CDN returns HTTP 403
            if let playerJS = playerJS, let transformed = transformNParam(url: url, playerJS: playerJS) {
                log("[Resolve] itag \(itag): n-param ")
                return transformed
            }
            log("[Resolve] itag \(itag): n-param not applied, using original URL")
            return url
        }

        // Case 2: signatureCipher
        if let cipher = format["signatureCipher"] as? String ?? format["cipher"] as? String {
            if let playerJS = playerJS {
                log("[Resolve] itag \(itag): signatureCipher, descrambling...")
                let result = descrambleSignatureCipher(cipher: cipher, playerJS: playerJS)
                log("[Resolve] itag \(itag): descramble \(result != nil ? "" : "")")
                return result
            } else {
                log("[Resolve] itag \(itag): signatureCipher but no player.js — skipping")
            }
        }

        return nil
    }

    /// Parse signatureCipher, descramble the signature using player.js, and construct the final URL.
    private static func descrambleSignatureCipher(cipher: String, playerJS: String) -> URL? {
        let params = parseCipherParams(cipher)
        guard let scrambledSig = params["s"],
              let encodedURL = params["url"] else {
            log("[Cipher]  Missing s or url in cipher params. Keys: \(params.keys.sorted())")
            return nil
        }

        guard let baseURLStr = encodedURL.removingPercentEncoding,
              var components = URLComponents(string: baseURLStr) else {
            log("[Cipher]  Could not decode URL from cipher")
            return nil
        }

        let sigParam = params["sp"] ?? "signature"
        let decodedSig = scrambledSig.removingPercentEncoding ?? scrambledSig

        guard let descrambledSig = executeSignatureDescramble(scrambledSig: decodedSig, playerJS: playerJS) else {
            log("[Cipher]  Signature descramble returned nil")
            return nil
        }
        log("[Cipher]  Descrambled sig (\(descrambledSig.count) chars)")

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: sigParam, value: descrambledSig))
        components.queryItems = queryItems

        guard let finalURL = components.url else { return nil }
        // Also transform n-parameter so CDN doesn't 403 the signed URL
        if let nTransformed = transformNParam(url: finalURL, playerJS: playerJS) {
            log("[Cipher]  n-param applied to cipher-resolved URL")
            return nTransformed
        }
        return finalURL
    }

    private static func parseCipherParams(_ cipher: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in cipher.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1])
            }
        }
        return result
    }

    /// Execute YouTube's signature descramble function using JavaScriptCore.
    private static func executeSignatureDescramble(scrambledSig: String, playerJS: String) -> String? {
        if let funcName = findScrambleFunctionName(in: playerJS) {
            log("[SigDescramble]  Found primary function: \(funcName)")
            if let funcCode = extractFunction(named: funcName, from: playerJS) {
                log("[SigDescramble]  Extracted primary code (\(funcCode.count) chars)")
                if let result = executeJS(funcCode, functionName: funcName, argument: scrambledSig), result != scrambledSig {
                    return result
                }
                log("[SigDescramble] Primary function execution failed, trying candidates")
            } else {
                log("[SigDescramble]  Could not extract primary function body for \(funcName)")
            }
        } else {
            log("[SigDescramble]  Could not find primary scramble function name")
        }

        let candidates = findCandidateScrambleFunctions(in: playerJS)
        log("[SigDescramble] Candidate functions: \(candidates.count)")

        for name in candidates.prefix(12) {
            guard let funcCode = extractFunction(named: name, from: playerJS) else { continue }
            if let result = executeJS(funcCode, functionName: name, argument: scrambledSig),
               result != scrambledSig,
               result.count >= max(8, scrambledSig.count / 2) {
                log("[SigDescramble]  Fallback candidate succeeded: \(name)")
                return result
            }
        }

        log("[SigDescramble]  All candidates failed")
        return nil
    }

    /// Find the name of the initial signature descramble function.
    private static func findScrambleFunctionName(in js: String) -> String? {
        // Multiple patterns YouTube uses to reference the sig descramble function
        let patterns = [
            // \b[cs]\s*&&\s*[adf]\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\(
            "\\b[cs]\\s*&&\\s*[adf]\\.set\\([^,]+\\s*,\\s*encodeURIComponent\\(([a-zA-Z0-9$]+)\\(",
            // \b[a-zA-Z0-9]+\s*&&\s*[a-zA-Z0-9]+\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\(
            "\\b[a-zA-Z0-9]+\\s*&&\\s*[a-zA-Z0-9]+\\.set\\([^,]+\\s*,\\s*encodeURIComponent\\(([a-zA-Z0-9$]+)\\(",
            // \bm=([a-zA-Z0-9$]{2,})\(decodeURIComponent\(h\.s\)\)
            "\\bm=([a-zA-Z0-9$]{2,})\\(decodeURIComponent\\(h\\.s\\)\\)",
            // \bc\s*=\s*a\.get\(b\)\)\s*&&\s*\(c\s*=\s*([a-zA-Z0-9$]+)\(
            "\\bc\\s*=\\s*a\\.get\\(b\\)\\)\\s*&&\\s*\\(c\\s*=\\s*([a-zA-Z0-9$]+)\\(",
            // Generic split/join signature function (param name is obfuscated)
            "(?:\\b|[^a-zA-Z0-9$])([a-zA-Z0-9$]{2,})\\s*=\\s*function\\(\\s*([a-zA-Z0-9_$]+)\\s*\\)\\s*\\{\\s*\\2\\s*=\\s*\\2\\.split\\(\\s*\"\"\\s*\\)",
            // Same pattern with single quotes
            "(?:\\b|[^a-zA-Z0-9$])([a-zA-Z0-9$]{2,})\\s*=\\s*function\\(\\s*([a-zA-Z0-9_$]+)\\s*\\)\\s*\\{\\s*\\2\\s*=\\s*\\2\\.split\\(\\s*'\\s*'\\s*\\)",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: js) else { continue }
            let name = String(js[range])
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// Broad fallback: collect all function names that look like signature transforms.
    private static func findCandidateScrambleFunctions(in js: String) -> [String] {
        let patterns = [
            "(?:\\b|[^a-zA-Z0-9$])([a-zA-Z0-9$]{2,})\\s*=\\s*function\\(\\s*([a-zA-Z0-9_$]+)\\s*\\)\\s*\\{\\s*\\2\\s*=\\s*\\2\\.split\\(\\s*\"\"\\s*\\)",
            "(?:\\b|[^a-zA-Z0-9$])([a-zA-Z0-9$]{2,})\\s*=\\s*function\\(\\s*([a-zA-Z0-9_$]+)\\s*\\)\\s*\\{\\s*\\2\\s*=\\s*\\2\\.split\\(\\s*'\\s*'\\s*\\)",
            "function\\s+([a-zA-Z0-9$]{2,})\\s*\\(\\s*([a-zA-Z0-9_$]+)\\s*\\)\\s*\\{\\s*\\2\\s*=\\s*\\2\\.split\\(\\s*\"\"\\s*\\)",
        ]

        var seen = Set<String>()
        var ordered: [String] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: js, range: NSRange(js.startIndex..., in: js))
            for match in matches {
                guard match.numberOfRanges >= 2,
                      let range = Range(match.range(at: 1), in: js) else { continue }
                let name = String(js[range])
                if !name.isEmpty && !seen.contains(name) {
                    seen.insert(name)
                    ordered.append(name)
                }
            }
        }

        return ordered
    }

    /// Extract a JavaScript function and all its dependencies (helper transformation objects).
    private static func extractFunction(named name: String, from js: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)

        // Find function definition using brace-balancing (handles nested braces)
        let funcPatterns = [
            "(?:var\\s+)?\(escapedName)\\s*=\\s*function\\([^)]*\\)\\s*\\{",
            "function\\s+\(escapedName)\\s*\\([^)]*\\)\\s*\\{",
        ]

        var funcBody: String?
        for pattern in funcPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
               let matchRange = Range(match.range, in: js) {
                // Brace-balance from the opening {
                guard let braceStart = js[matchRange].lastIndex(of: "{") else { continue }
                var depth = 0
                var current = braceStart
                for ch in js[braceStart...] {
                    if ch == "{" { depth += 1 }
                    if ch == "}" { depth -= 1 }
                    if depth == 0 {
                        funcBody = String(js[matchRange.lowerBound...current])
                        break
                    }
                    current = js.index(after: current)
                }
                if funcBody != nil { break }
            }
        }
        guard let body = funcBody else { return nil }

        // Find the helper object used in the function (e.g., Xc.Ab(...), Xc.wR(...))
        // Pattern: <objName>.<methodName>(a, <number>)
        var code = body
        if let helperRegex = try? NSRegularExpression(pattern: "([a-zA-Z0-9$]{2,})\\.[a-zA-Z0-9$]+\\(", options: []),
           let helperMatch = helperRegex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           helperMatch.numberOfRanges >= 2,
           let helperRange = Range(helperMatch.range(at: 1), in: body) {
            let helperName = String(body[helperRange])
            // Extract the helper object definition: var <helperName>={...};
            if let helperCode = extractHelperObject(named: helperName, from: js) {
                code = helperCode + "\n" + body
            }
        }

        return code
    }

    /// Extract a helper object definition like: var Xc={Ab:function(a){...},wR:function(a,b){...}};
    private static func extractHelperObject(named name: String, from js: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "var\\s+\(escapedName)\\s*=\\s*\\{"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
              let matchRange = Range(match.range, in: js) else { return nil }

        // Find the matching closing brace, accounting for nested braces
        let startOfObj = js.index(matchRange.upperBound, offsetBy: -1) // back to {
        var depth = 0
        var current = startOfObj

        for ch in js[startOfObj...] {
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1 }
            if depth == 0 {
                let fullStart = matchRange.lowerBound
                var end = js.index(after: current)
                if end < js.endIndex && js[end] == ";" { end = js.index(after: end) }
                return String(js[fullStart..<end])
            }
            current = js.index(after: current)
        }
        return nil
    }

    /// Handle YouTube's n-parameter throttle avoidance.
    /// Without this, the CDN returns HTTP 403 on stream requests.
    private static func transformNParam(url: URL, playerJS: String?) -> URL? {
        guard let playerJS = playerJS else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let nIndex = queryItems.firstIndex(where: { $0.name == "n" }),
              let nValue = queryItems[nIndex].value else {
            return nil
        }

        log("[NParam] Transforming n-value (\(nValue.count) chars)...")

        let candidatePlayers: [(label: String, js: String)] = {
            if let fallback = _trustedFallbackPlayerJS, fallback != playerJS {
                return [("page player", playerJS), ("trusted fallback player", fallback)]
            }
            return [("page player", playerJS)]
        }()

        for candidate in candidatePlayers {
            guard let nFunc = extractNTransformFunction(from: candidate.js) else {
                log("[NParam] \(candidate.label): could not extract n-transform function")
                continue
            }

            log("[NParam] \(candidate.label): executing function \(nFunc.name)")
            guard let transformed = executeJS(nFunc.code, functionName: nFunc.name, argument: nValue),
                  transformed != nValue else {
                log("[NParam] \(candidate.label): transform returned same/nil value")
                continue
            }

            log("[NParam]  \(candidate.label) transformed n-param (\(nValue.count)→\(transformed.count) chars)")
            var newItems = queryItems
            newItems[nIndex] = URLQueryItem(name: "n", value: transformed)
            components.queryItems = newItems
            return components.url
        }

        log("[NParam]  Could not transform n-param with any player.js")
        return nil
    }

    /// Extract the n-parameter transform function from player.js.
    private static func extractNTransformFunction(from js: String) -> (code: String, name: String)? {
        // Modern player.js uses array-indexed form: b=Xb[0](b) - try this first
        let arrayIndexedPatterns = [
            "\\.get\\(\"n\"\\)\\)&&\\(b=([a-zA-Z0-9$]+)\\[(\\d+)\\]\\(b\\)",
            "b&&\\(b=([a-zA-Z0-9$]+)\\[(\\d+)\\]\\(b\\)",
            // NewPipe-style: .get("n"))&&(x=Func[0](x)
            "\\.get\\(\\\"n\\\"\\)\\)&&\\([a-zA-Z0-9$]=([a-zA-Z0-9$]+)(?:\\[(\\d+)\\])?\\([a-zA-Z0-9$]\\)",
            // Newer obfuscation: a.D&&(b=\"nn\"[+a.D],c=a.get(b))&&(c=Func[0](c)
            "=\\\"nn\\\"\\[\\+[a-zA-Z0-9$]+\\.[a-zA-Z0-9$]+\\],[a-zA-Z0-9$]+=[a-zA-Z0-9$]+\\.get\\([a-zA-Z0-9$]+\\)\\)\\&\\&\\([a-zA-Z0-9$]+=([a-zA-Z0-9$]+)(?:\\[(\\d+)\\])?\\([a-zA-Z0-9$]\\)",
        ]
        for pattern in arrayIndexedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
                  match.numberOfRanges >= 3,
                  let nameRange = Range(match.range(at: 1), in: js),
                  let idxRange = Range(match.range(at: 2), in: js) else { continue }
            let arrName = String(js[nameRange])
            let idx = Int(js[idxRange]) ?? 0
            log("[NParam] Found array-indexed reference: \(arrName)[\(idx)]")
            if let result = extractFunctionFromArray(named: arrName, index: idx, from: js) {
                return result
            }
        }

        // Older direct-call form: b=Xb(b)
        let directPatterns = [
            "\\.get\\(\"n\"\\)\\)&&\\(b=([a-zA-Z0-9$]+)\\(b\\)",
            "var\\s+b=a\\.get\\(\"n\"\\).*?b=([a-zA-Z0-9$]+)\\(b\\)",
            "nfct=\"?([a-zA-Z0-9$]+)\"?",
        ]
        for pattern in directPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: js) else { continue }
            let funcName = String(js[range])
            log("[NParam] Found direct reference: \(funcName)")
            if let code = extractCompleteFunction(named: funcName, from: js) {
                return (stripNFunctionEarlyReturnGuard(in: code), funcName)
            }
        }

        // NewPipe/yt-dlp style fallback: locate sentinel (_w8_) table index, then
        // locate a function with catch { return TABLE[idx] + arg }.
        if let fallback = extractNTransformFunctionViaSentinel(from: js) {
            return fallback
        }
        return nil
    }

    /// Remove guard code that returns the input unchanged when an external symbol is undefined.
    /// NewPipe does this to make standalone n-functions executable outside full player scope.
    private static func stripNFunctionEarlyReturnGuard(in functionCode: String) -> String {
        let patterns = [
            "if\\s*\\(\\s*typeof\\s+[A-Za-z0-9$]+\\s*===?\\s*['\\\"]undefined['\\\"]\\s*\\)\\s*return\\s+[A-Za-z0-9$]+\\s*;",
            "if\\s*\\(\\s*typeof\\s+[A-Za-z0-9$]+\\s*===?\\s*\\\"undefined\\\"\\s*\\)\\s*return\\s+[A-Za-z0-9$]+\\s*;",
        ]
        var out = functionCode
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p, options: []) else { continue }
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        return out
    }

    /// Fallback n-function extraction based on the `_w8_` sentinel return form.
    /// This mirrors the robust strategy used by Android's extractor stack.
    private static func extractNTransformFunctionViaSentinel(from js: String) -> (code: String, name: String)? {
        guard let sentinel = findSentinelTableInfo(in: js) else { return nil }

        let escapedVar = NSRegularExpression.escapedPattern(for: sentinel.tableVar)
        let returnPattern = "return\\s+\(escapedVar)\\[\(sentinel.index)\\]\\s*\\+\\s*([A-Za-z0-9$]+)"
        guard let returnRegex = try? NSRegularExpression(pattern: returnPattern, options: []) else {
            return nil
        }

        let returnMatches = returnRegex.matches(in: js, range: NSRange(js.startIndex..., in: js))
        for ret in returnMatches {
            guard ret.numberOfRanges >= 2,
                  let argRange = Range(ret.range(at: 1), in: js) else { continue }
            let argName = String(js[argRange])

            guard let location = Range(ret.range(at: 0), in: js)?.lowerBound,
                let locationOffset = Optional(js.distance(from: js.startIndex, to: location)),
                  let enclosing = findEnclosingAssignedFunction(containingOffset: locationOffset, in: js) else {
                continue
            }

            // Require that the sentinel return appends the enclosing function argument.
            guard argName == enclosing.argument else {
                continue
            }

            let funcName = enclosing.name
            let funcCode = enclosing.code
            guard isLikelyNTransformFunction(funcCode, name: funcName, sentinel: sentinel) else {
                log("[NParam] Sentinel fallback rejected candidate: \(funcName)")
                continue
            }

            var preludeParts: [String] = []
            if let tableDecl = sentinel.tableDeclaration {
                preludeParts.append(tableDecl)
            }

            // Some current players gate the transform with `typeof ZD1 === ...`.
            // If undefined, they immediately return the original n-value.
            if let guardVar = extractTypeofGuardVariable(from: funcCode) {
                if let decl = extractVarDeclaration(named: guardVar, from: js) {
                    preludeParts.append(decl)
                } else {
                    preludeParts.append("var \(guardVar)=1;")
                }
            }

            let fullCode = (preludeParts + [funcCode]).joined(separator: "\n")
            log("[NParam] Sentinel fallback matched function: \(funcName) using \(sentinel.tableVar)[\(sentinel.index)]")
            return (stripNFunctionEarlyReturnGuard(in: fullCode), funcName)
        }
        return nil
    }

    private static func findEnclosingAssignedFunction(
        containingOffset offset: Int,
        in js: String
    ) -> (name: String, argument: String, code: String)? {
        let pattern = "([A-Za-z0-9$]+)\\s*=\\s*function\\(\\s*([A-Za-z0-9$]+)\\s*\\)\\s*\\{"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

        let matches = regex.matches(in: js, range: NSRange(js.startIndex..., in: js))
        var best: (start: Int, name: String, arg: String, code: String)?

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: js),
                  let nameRange = Range(match.range(at: 1), in: js),
                  let argRange = Range(match.range(at: 2), in: js),
                  let braceStart = js[fullRange].lastIndex(of: "{") else {
                continue
            }

            let startOffset = js.distance(from: js.startIndex, to: fullRange.lowerBound)
            if startOffset > offset { break }

            var depth = 0
            var current = braceStart
            var endOffset: Int?
            while current < js.endIndex {
                let ch = js[current]
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        endOffset = js.distance(from: js.startIndex, to: current)
                        break
                    }
                }
                current = js.index(after: current)
            }

            guard let end = endOffset, end >= offset else { continue }

            let name = String(js[nameRange])
            let arg = String(js[argRange])
            let code = String(js[fullRange.lowerBound...current])

            if let existing = best {
                if startOffset > existing.start {
                    best = (startOffset, name, arg, code)
                }
            } else {
                best = (startOffset, name, arg, code)
            }
        }

        if let best {
            return (best.name, best.arg, best.code)
        }
        return nil
    }

    private static func isLikelyNTransformFunction(
        _ functionCode: String,
        name: String,
        sentinel: (tableVar: String, index: Int, tableDeclaration: String?)
    ) -> Bool {
        // Reject constructor-style helpers that are common false positives.
        if functionCode.contains("instanceof \(name)") || functionCode.contains("this.") {
            return false
        }

        // Require sentinel catch-return signature in the body.
        let escapedVar = NSRegularExpression.escapedPattern(for: sentinel.tableVar)
        let sentinelPattern = "return\\s+\(escapedVar)\\[\(sentinel.index)\\]\\s*\\+"
        guard let regex = try? NSRegularExpression(pattern: sentinelPattern, options: []),
              regex.firstMatch(in: functionCode, range: NSRange(functionCode.startIndex..., in: functionCode)) != nil else {
            return false
        }

        // n-transform functions are string-in/string-out and usually end with a join call.
        guard functionCode.contains("return") else { return false }
        return true
    }

    private static func extractTypeofGuardVariable(from functionCode: String) -> String? {
        let pattern = "typeof\\s+([A-Za-z0-9$]+)\\s*==="
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: functionCode, range: NSRange(functionCode.startIndex..., in: functionCode)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: functionCode) else {
            return nil
        }
        return String(functionCode[range])
    }

    private static func extractVarDeclaration(named varName: String, from js: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: varName)
        let pattern = "var\\s+\(escapedName)\\s*=\\s*[^;]+;"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
              let range = Range(match.range, in: js) else {
            return nil
        }
        return String(js[range])
    }

    private static func findSentinelTableInfo(in js: String) -> (tableVar: String, index: Int, tableDeclaration: String?)? {
        // Form 1: var G=["..._w8_...", ...]
        let arrayVarPattern = "var\\s+([A-Za-z0-9$]+)\\s*=\\s*\\["
        if let regex = try? NSRegularExpression(pattern: arrayVarPattern, options: []) {
            let nsRange = NSRange(js.startIndex..., in: js)
            let matches = regex.matches(in: js, range: nsRange)
            for m in matches {
                guard m.numberOfRanges >= 2,
                    let nameRange = Range(m.range(at: 1), in: js) else { continue }
                let tableVar = String(js[nameRange])
                guard let decl = extractArrayVarDeclaration(named: tableVar, from: js) else { continue }
                guard let bodyStart = decl.firstIndex(of: "["),
                    let bodyEnd = decl.lastIndex(of: "]"),
                    bodyStart < bodyEnd else { continue }
                let body = String(decl[decl.index(after: bodyStart)..<bodyEnd])
                let stringPattern = "\\\"([^\\\"]*)\\\"|\\'([^\\']*)\\'"
                guard let sRegex = try? NSRegularExpression(pattern: stringPattern, options: []) else { continue }
                let sMatches = sRegex.matches(in: body, range: NSRange(body.startIndex..., in: body))
                for (idx, sm) in sMatches.enumerated() {
                    var val: String?
                    if let r1 = Range(sm.range(at: 1), in: body), sm.range(at: 1).location != NSNotFound {
                        val = String(body[r1])
                    } else if let r2 = Range(sm.range(at: 2), in: body), sm.range(at: 2).location != NSNotFound {
                        val = String(body[r2])
                    }
                    if let v = val, v.contains("_w8_") {
                        return (tableVar, idx, decl)
                    }
                }
            }
        }

        // Form 2: var C="..._w8_...".split(";")
        let splitPattern = "var\\s+([A-Za-z0-9$]+)\\s*=\\s*\\\"([^\\\"]*_w8_[^\\\"]*)\\\"\\.split\\(\\\";\\\"\\)"
        if let regex = try? NSRegularExpression(pattern: splitPattern, options: []),
           let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
           match.numberOfRanges >= 3,
           let nameRange = Range(match.range(at: 1), in: js),
           let blobRange = Range(match.range(at: 2), in: js),
           let fullRange = Range(match.range(at: 0), in: js) {
            let tableVar = String(js[nameRange])
            let blob = String(js[blobRange])
            let parts = blob.split(separator: ";", omittingEmptySubsequences: false)
            if let idx = parts.firstIndex(where: { $0.contains("_w8_") }) {
                let decl = String(js[fullRange]) + ";"
                return (tableVar, idx, decl)
            }
        }

        return nil
    }

    private static func extractArrayVarDeclaration(named varName: String, from js: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: varName)
        let pattern = "var\\s+\(escapedName)\\s*=\\s*\\["
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
              let matchRange = Range(match.range, in: js),
              let openBracket = js[matchRange].lastIndex(of: "[") else {
            return nil
        }

        var depth = 0
        var inSingle = false
        var inDouble = false
        var escaped = false
        var endIdx: String.Index?

        for i in js.indices[openBracket...] {
            let ch = js[i]

            if escaped {
                escaped = false
                continue
            }

            if ch == "\\" {
                if inSingle || inDouble {
                    escaped = true
                }
                continue
            }

            if ch == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if ch == "'" && !inDouble {
                inSingle.toggle()
                continue
            }

            if inSingle || inDouble { continue }

            if ch == "[" { depth += 1 }
            if ch == "]" {
                depth -= 1
                if depth == 0 {
                    endIdx = i
                    break
                }
            }
        }

        guard let end = endIdx else { return nil }
        let start = matchRange.lowerBound
        var afterEnd = js.index(after: end)
        if afterEnd < js.endIndex, js[afterEnd] == ";" {
            afterEnd = js.index(after: afterEnd)
            return String(js[start..<afterEnd])
        }
        return String(js[start..<afterEnd]) + ";"
    }

    /// Extract the function at `index` from a JS array variable: var Name=[function(a){...},...].
    private static func extractFunctionFromArray(named arrayName: String, index: Int, from js: String) -> (code: String, name: String)? {
        let escapedName = NSRegularExpression.escapedPattern(for: arrayName)
        // Match: var Name=[ or Name=[ followed by optional space and `function`
        let pattern = "(?:var\\s+)?\(escapedName)\\s*=\\s*\\[\\s*function\\s*\\(([^)]*)\\)\\s*\\{"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
              let matchRange = Range(match.range, in: js) else { return nil }

        // The match ends right after the opening `{` - step back one to get to it
        let braceIdx = js.index(before: matchRange.upperBound)

        let paramStr: String
        if match.numberOfRanges >= 2, let pRange = Range(match.range(at: 1), in: js) {
            paramStr = String(js[pRange])
        } else {
            paramStr = "a"
        }

        // Brace-balance to extract the complete function body {…}
        var depth = 0
        var current = braceIdx
        var idx = js.startIndex
        for (i, ch) in js[braceIdx...].enumerated() {
            idx = js.index(braceIdx, offsetBy: i)
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1 }
            if depth == 0 {
                let funcBody = String(js[braceIdx...idx])
                let syntheticName = "__nfunc_\(arrayName)"
                let code = "var \(syntheticName) = function(\(paramStr)) \(funcBody);"
                return (code, syntheticName)
            }
        }
        return nil
    }

    /// Extract a complete function definition including multi-line body with nested braces.
    private static func extractCompleteFunction(named name: String, from js: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "\(escapedName)\\s*=\\s*function\\([^)]*\\)\\s*\\{",
            "function\\s+\(escapedName)\\s*\\([^)]*\\)\\s*\\{",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
                  let matchRange = Range(match.range, in: js) else { continue }

            // Find opening brace
            guard let braceStart = js[matchRange].lastIndex(of: "{") else { continue }

            // Balance braces to find full function body
            var depth = 0
            var current = braceStart
            for ch in js[braceStart...] {
                if ch == "{" { depth += 1 }
                if ch == "}" { depth -= 1 }
                if depth == 0 {
                    return String(js[matchRange.lowerBound...current])
                }
                current = js.index(after: current)
            }
        }
        return nil
    }

    /// Execute a JavaScript function by name with a single string argument using JavaScriptCore.
    private static func executeJS(_ code: String, functionName: String, argument: String) -> String? {
        let ctx = JSContext()!
        var jsError: String?
        ctx.exceptionHandler = { _, exception in
            jsError = exception?.toString()
        }

        ctx.evaluateScript(code)
        if let err = jsError {
            log("[JSContext]  Error evaluating code: \(err)")
            return nil
        }

        let escapedArg = argument
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let callScript = "\(functionName)('\(escapedArg)')"

        let result = ctx.evaluateScript(callScript)
        if let err = jsError {
            log("[JSContext]  Error calling \(functionName): \(err)")
            return nil
        }

        if let str = result?.toString(), result?.isString == true {
            return str
        }
        // Also accept if the result is not undefined/null
        if let str = result?.toString(), str != "undefined" && str != "null" {
            return str
        }
        log("[JSContext]  Result was \(result?.toString() ?? "nil")")
        return nil
    }

    // MARK: - Strategy 2: Piped API

    private static let fallbackPipedInstances = [
        "https://pipedapi.tokhmi.xyz",
        "https://pipedapi.moodkiller.moe",
        "https://pipedapi.syncpundit.io",
        "https://api.piped.yt",
        "https://pipedapi.kavin.rocks",
        "https://pipedapi.adminforge.de",
        "https://pipedapi.moomoo.me",
        "https://api.piped.privacydev.net",
    ]

    private static func resolveViaPiped(videoId: String) async -> StreamInfo? {
        log("[Piped] Fetching instances...")
        let fetched = await fetchPipedInstances()
        let instances = mergedInstances(primary: fetched, fallback: fallbackPipedInstances)
        log("[Piped] Trying \(min(instances.count, 8)) instances")

        for instance in instances.prefix(8) {
            let candidates = pipedStreamEndpointCandidates(instance: instance, videoId: videoId)
            for apiURL in candidates {
                do {
                    var request = URLRequest(url: apiURL)
                    request.timeoutInterval = 8
                    request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        log("[Piped] \(instance): non-HTTP response")
                        continue
                    }
                    guard (200...299).contains(http.statusCode) else {
                        log("[Piped] \(instance): HTTP \(http.statusCode)")
                        continue
                    }
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        log("[Piped] \(instance): non-JSON response")
                        continue
                    }
                    if json["error"] as? String != nil {
                        log("[Piped] \(instance): error response")
                        continue
                    }

                    if let hls = json["hls"] as? String, let url = URL(string: hls) {
                        log("[Piped]  HLS from \(instance)")
                        return StreamInfo(url: url, isHLS: true)
                    }

                    if let streams = json["videoStreams"] as? [[String: Any]] {
                        let muxed = streams.filter { ($0["videoOnly"] as? Bool) == false }
                        let target = muxed.isEmpty ? streams : muxed
                        let best = target
                            .filter { ($0["url"] as? String) != nil }
                            .filter { ($0["height"] as? Int ?? 0) >= 1080 || ($0["height"] as? Int ?? 0) == 0 }
                            .sorted { a, b in
                                let ac = codecPriority(a["mimeType"] as? String)
                                let bc = codecPriority(b["mimeType"] as? String)
                                if ac != bc { return ac < bc }
                                return (a["bitrate"] as? Int ?? 0) > (b["bitrate"] as? Int ?? 0)
                            }
                            .first
                        if let urlStr = best?["url"] as? String, let url = URL(string: urlStr) {
                            return StreamInfo(url: url, isHLS: false)
                        }
                    }
                } catch {
                    log("[Piped] \(instance): \(error.localizedDescription)")
                    continue
                }
            }
        }
        log("[Piped]  No instance returned a stream")
        return nil
    }

    private static func pipedStreamEndpointCandidates(instance: String, videoId: String) -> [URL] {
        let apiBase = instance.contains("/api/v1") ? instance : instance + "/api/v1"
        guard let url = URL(string: "\(apiBase)/streams/\(videoId)") else { return [] }
        return [url]
    }

    private static func fetchPipedInstances() async -> [String]? {
        let registryURLs = [
            "https://piped-instances.kavin.rocks/",
            "https://instances.piped.video/",
        ]
        for urlStr in registryURLs {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                guard let instances = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
                let result = instances.compactMap { inst -> String? in
                    guard let apiUrl = inst["api_url"] as? String, !apiUrl.isEmpty else { return nil }
                    return apiUrl.hasSuffix("/") ? String(apiUrl.dropLast()) : apiUrl
                }
                if !result.isEmpty { return result }
            } catch { continue }
        }
        return nil
    }

    // MARK: - Strategy 3: Invidious API

    private static let fallbackInvidiousInstances = [
        "https://invidious.fdn.fr",
        "https://iv.datura.network",
        "https://invidious.0011.lt",
        "https://inv.tux.pizza",
        "https://yewtu.be",
        "https://inv.nadeko.net",
        "https://invidious.privacydev.net",
        "https://invidious.nerdvpn.de",
    ]

    private static func resolveViaInvidious(videoId: String) async -> StreamInfo? {
        log("[Invidious] Fetching instances...")
        let fetched = await fetchInvidiousInstances()
        let instances = mergedInstances(primary: fetched, fallback: fallbackInvidiousInstances)
        log("[Invidious] Trying \(min(instances.count, 8)) instances")

        for instance in instances.prefix(8) {
            guard let apiURL = URL(string: "\(instance)/api/v1/videos/\(videoId)") else { continue }
            do {
                var request = URLRequest(url: apiURL)
                request.timeoutInterval = 8
                request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    log("[Invidious] \(instance): non-HTTP response")
                    continue
                }
                guard (200...299).contains(http.statusCode) else {
                    log("[Invidious] \(instance): HTTP \(http.statusCode)")
                    continue
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    log("[Invidious] \(instance): non-JSON response")
                    continue
                }
                if json["error"] as? String != nil { continue }

                if let hls = json["hlsUrl"] as? String, let url = URL(string: hls) {
                    log("[Invidious]  HLS from \(instance)")
                    return StreamInfo(url: url, isHLS: true)
                }

                let formatStreams = json["formatStreams"] as? [[String: Any]] ?? []
                let adaptiveFormats = json["adaptiveFormats"] as? [[String: Any]] ?? []
                let combined = formatStreams + adaptiveFormats

                let playable = combined.filter { format in
                    guard let url = format["url"] as? String, URL(string: url) != nil else { return false }
                    guard let mime = (format["type"] as? String)?.lowercased() else { return true }
                    return mime.contains("video/mp4") || mime.contains("video/webm")
                }

                let best = playable
                    .filter { format in
                        let height = parseHeight(format["qualityLabel"] as? String) ?? 0
                        return height >= 1080 || height == 0
                    }
                    .sorted { a, b in
                        let ac = codecPriority(a["type"] as? String)
                        let bc = codecPriority(b["type"] as? String)
                        if ac != bc { return ac < bc }
                        let aq = parseHeight(a["qualityLabel"] as? String) ?? 0
                        let bq = parseHeight(b["qualityLabel"] as? String) ?? 0
                        return aq > bq
                    }
                    .first

                if let urlStr = best?["url"] as? String, let url = URL(string: urlStr) {
                    return StreamInfo(url: url, isHLS: false)
                }
            } catch {
                log("[Invidious] \(instance): \(error.localizedDescription)")
                continue
            }
        }
        log("[Invidious] \u{2717} No instance returned a stream")
        return nil
    }

    private static func mergedInstances(primary: [String]?, fallback: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for item in (primary ?? []) + fallback {
            let normalized = item.hasSuffix("/") ? String(item.dropLast()) : item
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                out.append(normalized)
            }
        }
        return out
    }

    private static func fetchInvidiousInstances() async -> [String]? {
        guard let url = URL(string: "https://api.invidious.io/instances.json?sort_by=health") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard let instances = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { return nil }
            return instances.compactMap { entry -> String? in
                guard entry.count >= 2,
                      let meta = entry[1] as? [String: Any],
                      let uri = meta["uri"] as? String,
                      let type = meta["type"] as? String,
                      type == "https",
                      meta["api"] as? Bool == true else { return nil }
                return uri
            }
        } catch { return nil }
    }

    // MARK: - Helpers

    private static func pickBestResolvedStream(
        from formats: [[String: Any]],
        playerJS: String?,
        mimeFilter: String?,
        minPreferredHeight: Int
    ) -> StreamInfo? {
        // Prefer >= minPreferredHeight while allowing a lower-quality fallback when needed.
        let filteredByMime = formats
            .filter { format in
                if let filter = mimeFilter {
                    guard let mime = format["mimeType"] as? String, mime.hasPrefix(filter) else { return false }
                }
                return true
            }

        let preferred = filteredByMime.filter { ($0["height"] as? Int ?? 0) >= minPreferredHeight || ($0["height"] as? Int ?? 0) == 0 }
        let candidates = preferred.isEmpty ? filteredByMime : preferred

        let sorted = candidates
            .sorted { a, b in
                let ac = codecPriority(a["mimeType"] as? String)
                let bc = codecPriority(b["mimeType"] as? String)
                if ac != bc { return ac < bc }
                let ah = a["height"] as? Int ?? 0
                let bh = b["height"] as? Int ?? 0
                return ah > bh
            }

        for format in sorted {
            if let url = resolveStreamURL(from: format, playerJS: playerJS) {
                return StreamInfo(url: url, isHLS: false)
            }
        }
        return nil
    }

    private static func codecPriority(_ mimeType: String?) -> Int {
        guard let mime = mimeType?.lowercased() else { return 4 }
        if mime.contains("avc1") { return 0 }
        if mime.contains("vp9") || mime.contains("vp09") { return 1 }
        if mime.contains("av01") { return 2 }
        return 3
    }

    private static func parseHeight(_ qualityLabel: String?) -> Int? {
        guard let label = qualityLabel else { return nil }
        return Int(label.replacingOccurrences(of: "p", with: "").trimmingCharacters(in: .whitespaces))
    }

    private static func extractJSONViaRegex(from html: String, pattern: String) -> [String: Any]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let matchRange = Range(match.range, in: html) else { return nil }
        return parseJSONObject(from: html, startingAt: matchRange.upperBound)
    }

    private static func parseJSONObject(from string: String, startingAt start: String.Index) -> [String: Any]? {
        guard start < string.endIndex, string[start] == "{" else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var current = start

        for ch in string[start...] {
            if escaped { escaped = false; current = string.index(after: current); continue }
            if ch == "\\" && inString { escaped = true; current = string.index(after: current); continue }
            if ch == "\"" { inString = !inString; current = string.index(after: current); continue }
            if inString { current = string.index(after: current); continue }
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1 }
            if depth == 0 {
                let jsonStr = String(string[start...current])
                return (try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8))) as? [String: Any]
            }
            current = string.index(after: current)
        }
        return nil
    }

    private static func extractEscapedJSON(from text: String) -> [String: Any]? {
        var result = ""
        var escaped = false
        for ch in text {
            if escaped {
                switch ch {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                default: result.append("\\"); result.append(ch)
                }
                escaped = false
                continue
            }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { break }
            result.append(ch)
        }
        guard let data = result.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - SponsorBlock API

/// SponsorBlock integration matching Android's SponsorBlockApi.
/// Fetches skip segments for YouTube videos to skip intros, sponsors, outros, etc.
enum SponsorBlockAPI {

    struct Segment {
        let startTime: Double
        let endTime: Double
        let category: String
    }

    static func getSkipSegments(videoId: String) async -> [Segment] {
        let categories = ["sponsor", "selfpromo", "intro", "outro", "interaction", "music_offtopic"]
        let categoriesParam = categories.map { "\"\($0)\"" }.joined(separator: ",")
        guard let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(videoId)&categories=[\(categoriesParam)]") else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            return array.compactMap { obj in
                guard let segment = obj["segment"] as? [Double],
                      segment.count >= 2,
                      let category = obj["category"] as? String else { return nil }
                return Segment(startTime: segment[0], endTime: segment[1], category: category)
            }
        } catch {
            return []
        }
    }

    /// Calculate the best start time, skipping intro/sponsor segments at the beginning.
    /// Returns a default 5s skip for the MPAA green screen / studio logos when no segments exist.
    static func calculateStartTime(segments: [Segment]) -> Double {
        let defaultSkip = 5.0
        if segments.isEmpty { return defaultSkip }

        let sorted = segments.sorted { $0.startTime < $1.startTime }
        var currentTime = 0.0
        for segment in sorted {
            if segment.startTime <= currentTime + 2.0 {
                currentTime = max(currentTime, segment.endTime)
            } else {
                break
            }
        }
        return max(currentTime, defaultSkip)
    }
}
