import Foundation
import JavaScriptCore

// MARK: - Auth

struct JellyfinAuthApi: ServerAuthApi {
    let client: HttpClient

    func authenticateByName(username: String, password: String) async throws -> AuthResult {
        struct Body: Encodable { let Username: String; let Pw: String }
        return try await client.request(
            "/Users/AuthenticateByName",
            method: "POST",
            body: Body(Username: username, Pw: password)
        )
    }

    func getCurrentUser() async throws -> ServerUser {
        try await client.request("/Users/Me")
    }

    func getPublicUsers() async throws -> [ServerUser] {
        try await client.request("/Users/Public")
    }

    func logout() async throws {
        try await client.requestVoid("/Sessions/Logout")
    }

    func supportsQuickConnect() async throws -> Bool {
        do {
            let _: String = try await client.request("/QuickConnect/Enabled")
            return true
        } catch {
            return false
        }
    }

    func initiateQuickConnect() async throws -> QuickConnectInfo? {
        try await client.request("/QuickConnect/Initiate", method: "POST")
    }

    func checkQuickConnectStatus(secret: String) async throws -> Bool {
        let info: QuickConnectInfo = try await client.request(
            "/QuickConnect/Connect",
            queryItems: [URLQueryItem(name: "Secret", value: secret)]
        )
        return info.authenticated
    }

    func authenticateWithQuickConnect(secret: String) async throws -> AuthResult {
        struct Body: Encodable { let Secret: String }
        return try await client.request(
            "/Users/AuthenticateWithQuickConnect",
            method: "POST",
            body: Body(Secret: secret)
        )
    }
}

// MARK: - System

struct JellyfinSystemApi: ServerSystemApi {
    let client: HttpClient

    func getPublicSystemInfo() async throws -> PublicSystemInfo {
        try await client.request("/System/Info/Public")
    }

    func getSystemInfo() async throws -> SystemInfo {
        try await client.request("/System/Info")
    }
}

// MARK: - Items

struct JellyfinItemsApi: ServerItemsApi {
    let client: HttpClient

    func getItems(request: GetItemsRequest) async throws -> ItemsResult {
        let userId = request.userId ?? client.userId ?? ""
        let query = buildQuery([
            ("StartIndex", request.startIndex.map(String.init)),
            ("Limit", request.limit.map(String.init)),
            ("Recursive", request.recursive.map(String.init)),
            ("SearchTerm", request.searchTerm),
            ("SortOrder", request.sortOrder?.rawValue),
            ("SortBy", request.sortBy?.map(\.rawValue).joined(separator: ",")),
            ("ParentId", request.parentId),
            ("Fields", request.fields?.map(\.rawValue).joined(separator: ",")),
            ("IncludeItemTypes", request.includeItemTypes?.map(\.apiValue).joined(separator: ",")),
            ("ExcludeItemTypes", request.excludeItemTypes?.map(\.apiValue).joined(separator: ",")),
            ("Filters", request.filters?.map(\.rawValue).joined(separator: ",")),
            ("IsFavorite", request.isFavorite.map(String.init)),
            ("MediaTypes", request.mediaTypes?.map(\.rawValue).joined(separator: ",")),
            ("ArtistIds", request.artistIds?.joined(separator: ",")),
            ("PersonIds", request.personIds?.joined(separator: ",")),
            ("StudioIds", request.studioIds?.joined(separator: ",")),
            ("Genres", request.genres?.joined(separator: ",")),
            ("GenreIds", request.genreIds?.joined(separator: ",")),
            ("Tags", request.tags?.joined(separator: ",")),
            ("Years", request.years?.map(String.init).joined(separator: ",")),
            ("Ids", request.ids?.joined(separator: ",")),
            ("EnableImages", request.enableImages.map(String.init)),
            ("ImageTypeLimit", request.imageTypeLimit.map(String.init)),
            ("EnableUserData", request.enableUserData.map(String.init)),
            ("GroupItemsIntoCollections", request.groupItems.map(String.init)),
            ("NameStartsWith", request.nameStartsWith),
            ("CollapseBoxSetItems", request.collapseBoxSetItems.map(String.init)),
            ("EnableTotalRecordCount", request.enableTotalRecordCount.map(String.init)),
        ])
        return try await client.request("/Users/\(userId)/Items", queryItems: query)
    }

    func getPlaylistItems(itemId: String, userId: String?) async throws -> ItemsResult {
        let cacheBust = String(Int(Date().timeIntervalSince1970 * 1000))
        let query = buildQuery([
            ("UserId", userId ?? client.userId),
            ("Fields", "PlaylistItemId"),
            ("_ts", cacheBust),
        ])
        return try await client.request("/Playlists/\(itemId)/Items", queryItems: query)
    }

    func getResumeItems(request: GetResumeItemsRequest) async throws -> ItemsResult {
        let userId = request.userId ?? client.userId ?? ""
        let query = buildQuery([
            ("StartIndex", request.startIndex.map(String.init)),
            ("Limit", request.limit.map(String.init)),
            ("ParentId", request.parentId),
            ("Fields", request.fields?.map(\.rawValue).joined(separator: ",")),
            ("IncludeItemTypes", request.includeItemTypes?.map(\.apiValue).joined(separator: ",")),
            ("ExcludeItemTypes", request.excludeItemTypes?.map(\.apiValue).joined(separator: ",")),
            ("MediaTypes", request.mediaTypes?.map(\.rawValue).joined(separator: ",")),
            ("EnableImages", request.enableImages.map(String.init)),
            ("ImageTypeLimit", request.imageTypeLimit.map(String.init)),
        ])
        return try await client.request("/Users/\(userId)/Items/Resume", queryItems: query)
    }

    func getLatestMedia(request: GetLatestMediaRequest) async throws -> [ServerItem] {
        let userId = request.userId ?? client.userId ?? ""
        let query = buildQuery([
            ("ParentId", request.parentId),
            ("Fields", request.fields?.map(\.rawValue).joined(separator: ",")),
            ("IncludeItemTypes", request.includeItemTypes?.map(\.apiValue).joined(separator: ",")),
            ("Limit", request.limit.map(String.init)),
            ("GroupItems", request.groupItems.map(String.init)),
            ("ImageTypeLimit", request.imageTypeLimit.map(String.init)),
        ])
        return try await client.request("/Users/\(userId)/Items/Latest", queryItems: query)
    }

    func getNextUp(request: GetNextUpRequest) async throws -> ItemsResult {
        let userId = request.userId ?? client.userId ?? ""
        let query = buildQuery([
            ("UserId", userId),
            ("StartIndex", request.startIndex.map(String.init)),
            ("Limit", request.limit.map(String.init)),
            ("Fields", request.fields?.map(\.rawValue).joined(separator: ",")),
            ("SeriesId", request.seriesId),
            ("EnableImages", request.enableImages.map(String.init)),
            ("ImageTypeLimit", request.imageTypeLimit.map(String.init)),
        ])
        return try await client.request("/Shows/NextUp", queryItems: query)
    }

    func getSimilarItems(itemId: String, limit: Int?) async throws -> ItemsResult {
        let query = buildQuery([
            ("UserId", client.userId),
            ("Limit", limit.map(String.init)),
        ])
        return try await client.request("/Items/\(itemId)/Similar", queryItems: query)
    }

    func getSeasons(seriesId: String, userId: String) async throws -> ItemsResult {
        let query = buildQuery([("UserId", userId)])
        return try await client.request("/Shows/\(seriesId)/Seasons", queryItems: query)
    }

    func getEpisodes(seriesId: String, seasonId: String, userId: String) async throws -> ItemsResult {
        let query = buildQuery([
            ("SeasonId", seasonId),
            ("UserId", userId),
            ("Fields", "Overview,Trickplay"),
        ])
        return try await client.request("/Shows/\(seriesId)/Episodes", queryItems: query)
    }

    func getAncestors(itemId: String) async throws -> [ServerItem] {
        let userId = client.userId ?? ""
        let query = buildQuery([("UserId", userId)])
        return try await client.request("/Items/\(itemId)/Ancestors", queryItems: query)
    }
}

// MARK: - User Library

struct JellyfinUserLibraryApi: ServerUserLibraryApi {
    let client: HttpClient

    func getItem(itemId: String) async throws -> ServerItem {
        let userId = client.userId ?? ""
        return try await client.request("/Users/\(userId)/Items/\(itemId)")
    }

    func getSpecialFeatures(itemId: String) async throws -> [ServerItem] {
        let userId = client.userId ?? ""
        return try await client.request("/Users/\(userId)/Items/\(itemId)/SpecialFeatures")
    }

    func getThemeMedia(itemId: String, userId: String, inheritFromParent: Bool) async throws -> AllThemeMediaResult {
        let query = buildQuery([
            ("UserId", userId),
            ("InheritFromParent", String(inheritFromParent)),
        ])
        return try await client.request("/Items/\(itemId)/ThemeMedia", queryItems: query)
    }

    func getIntros(itemId: String) async throws -> [ServerItem] {
        let result: ItemsResult = try await client.request("/Items/\(itemId)/Intros")
        return result.items
    }

    func getLocalTrailers(itemId: String) async throws -> [ServerItem] {
        let userId = client.userId ?? ""
        let result: ItemsResult = try await client.request("/Users/\(userId)/Items/\(itemId)/LocalTrailers")
        return result.items
    }

    func deleteItem(itemId: String) async throws {
        try await client.requestVoid("/Items/\(itemId)", method: "DELETE")
    }

    func searchRemoteSubtitles(itemId: String, language: String) async throws -> [RemoteSubtitleResult] {
        return try await client.request("/Items/\(itemId)/RemoteSearch/Subtitles/\(language)")
    }

    func downloadRemoteSubtitle(itemId: String, subtitleId: String) async throws {
        try await client.requestVoid("/Items/\(itemId)/RemoteSearch/Subtitles/\(subtitleId)", method: "POST")
    }

    func markFavorite(itemId: String, userId: String) async throws -> UserItemData {
        try await client.request("/Users/\(userId)/FavoriteItems/\(itemId)", method: "POST")
    }

    func unmarkFavorite(itemId: String, userId: String) async throws -> UserItemData {
        try await client.request("/Users/\(userId)/FavoriteItems/\(itemId)", method: "DELETE")
    }

    func markPlayed(itemId: String, userId: String) async throws -> UserItemData {
        try await client.request("/Users/\(userId)/PlayedItems/\(itemId)", method: "POST")
    }

    func unmarkPlayed(itemId: String, userId: String) async throws -> UserItemData {
        try await client.request("/Users/\(userId)/PlayedItems/\(itemId)", method: "DELETE")
    }
}

// MARK: - Playback

struct JellyfinPlaybackApi: ServerPlaybackApi {
    let client: HttpClient

    func getPlaybackInfo(itemId: String, request: PlaybackInfoRequest) async throws -> PlaybackInfoResult {
        try await client.request("/Items/\(itemId)/PlaybackInfo", method: "POST", body: request)
    }

    func getVideoStreamUrl(itemId: String, params: StreamParams) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        let path = (!params.isLiveTv && params.liveStreamId == nil)
            ? "/Videos/\(itemId)/stream.\(params.container)"
            : "/Videos/\(itemId)/stream"
        guard var components = URLComponents(string: "\(base)\(path)") else {
            return "\(base)\(path)"
        }

        var queryItems: [URLQueryItem] = [URLQueryItem(name: "Static", value: "true")]
        if !params.mediaSourceId.isEmpty { queryItems.append(URLQueryItem(name: "MediaSourceId", value: params.mediaSourceId)) }
        if !params.playSessionId.isEmpty { queryItems.append(URLQueryItem(name: "PlaySessionId", value: params.playSessionId)) }
        if let liveStreamId = params.liveStreamId, !liveStreamId.isEmpty {
            queryItems.append(URLQueryItem(name: "LiveStreamId", value: liveStreamId))
        }
        queryItems.append(URLQueryItem(name: "DeviceId", value: params.deviceId))
        if let idx = params.audioStreamIndex { queryItems.append(URLQueryItem(name: "AudioStreamIndex", value: String(idx))) }
        if let idx = params.subtitleStreamIndex { queryItems.append(URLQueryItem(name: "SubtitleStreamIndex", value: String(idx))) }
        if let token = client.accessToken, !token.isEmpty { queryItems.append(URLQueryItem(name: "api_key", value: token)) }

        components.queryItems = queryItems
        return components.url?.absoluteString ?? "\(base)\(path)"
    }

    func getAudioStreamUrl(itemId: String, params: StreamParams) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        let path = "\(base)/Audio/\(itemId)/stream.\(params.container)"
        guard var components = URLComponents(string: path) else { return path }

        var queryItems: [URLQueryItem] = [URLQueryItem(name: "Static", value: "true")]
        if !params.mediaSourceId.isEmpty { queryItems.append(URLQueryItem(name: "MediaSourceId", value: params.mediaSourceId)) }
        if !params.playSessionId.isEmpty { queryItems.append(URLQueryItem(name: "PlaySessionId", value: params.playSessionId)) }
        queryItems.append(URLQueryItem(name: "DeviceId", value: params.deviceId))
        if let token = client.accessToken, !token.isEmpty { queryItems.append(URLQueryItem(name: "api_key", value: token)) }

        components.queryItems = queryItems
        return components.url?.absoluteString ?? path
    }

    func reportPlaybackStart(info: PlaybackStartReport) async throws {
        try await client.requestVoid("/Sessions/Playing", body: info)
    }

    func reportPlaybackProgress(info: PlaybackProgressReport) async throws {
        try await client.requestVoid("/Sessions/Playing/Progress", body: info)
    }

    func reportPlaybackStopped(info: PlaybackStopReport) async throws {
        try await client.requestVoid("/Sessions/Playing/Stopped", body: info)
    }
}

// MARK: - Image

struct JellyfinImageApi: ServerImageApi {
    let client: HttpClient

    func getItemImageUrl(itemId: String, imageType: ImageType, maxWidth: Int?, maxHeight: Int?, tag: String?) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        var url = "\(base)/Items/\(itemId)/Images/\(imageType.rawValue)"
        var params: [String] = []
        if let w = maxWidth { params.append("maxWidth=\(w)") }
        if let h = maxHeight { params.append("maxHeight=\(h)") }
        if let t = tag { params.append("tag=\(t)") }
        if !params.isEmpty { url += "?" + params.joined(separator: "&") }
        return url
    }

    func getChapterImageUrl(itemId: String, chapterIndex: Int, maxWidth: Int?, tag: String?) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        var url = "\(base)/Items/\(itemId)/Images/Chapter/\(chapterIndex)"
        var params: [String] = []
        if let w = maxWidth { params.append("maxWidth=\(w)") }
        if let t = tag { params.append("tag=\(t)") }
        if !params.isEmpty { url += "?" + params.joined(separator: "&") }
        return url
    }

    func getUserImageUrl(userId: String, imageType: ImageType, tag: String?) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        var url = "\(base)/Users/\(userId)/Images/\(imageType.rawValue)"
        if let t = tag { url += "?tag=\(t)" }
        return url
    }
}

// MARK: - Session

struct JellyfinSessionApi: ServerSessionApi {
    let client: HttpClient

    func postCapabilities(_ capabilities: ClientCapabilities) async throws {
        try await client.requestVoid("/Sessions/Capabilities/Full", body: capabilities)
    }

    func getSessions() async throws -> [SessionInfo] {
        try await client.request("/Sessions")
    }
}

// MARK: - User Views

struct JellyfinUserViewsApi: ServerUserViewsApi {
    let client: HttpClient

    func getUserViews(userId: String) async throws -> [ServerItem] {
        struct ViewsResponse: Decodable {
            let Items: [ServerItem]
        }
        let response: ViewsResponse = try await client.request("/Users/\(userId)/Views")
        return response.Items
    }
}

struct JellyfinAdminPluginsApi: ServerAdminPluginsApi {
    let client: HttpClient

    func getInstalledPlugins() async throws -> [ServerPluginInfo] {
        try await client.request("/Plugins")
    }
}

struct JellyfinHomeScreenSectionsApi: ServerHomeScreenSectionsApi {
    let client: HttpClient

    private struct SectionsResponse: Decodable {
        let items: [HomeScreenSectionInfo]

        enum CodingKeys: String, CodingKey {
            case items = "Items"
        }

        init(from decoder: Decoder) throws {
            if var list = try? decoder.unkeyedContainer() {
                var decoded: [HomeScreenSectionInfo] = []
                while !list.isAtEnd {
                    decoded.append(try list.decode(HomeScreenSectionInfo.self))
                }
                items = decoded
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = (try? container.decodeIfPresent([HomeScreenSectionInfo].self, forKey: .items)) ?? []
        }
    }

    func getMeta() async throws -> HomeScreenMeta {
        try await client.request("/HomeScreen/Meta")
    }

    func getUserSections() async throws -> [HomeScreenSectionInfo] {
        let query = buildQuery([("userId", client.userId)])
        let response: SectionsResponse = try await client.request("/HomeScreen/Sections", queryItems: query)
        return response.items
    }

    func getSectionItems(sectionType: String, additionalData: String?) async throws -> ItemsResult {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let encodedSection = sectionType.addingPercentEncoding(withAllowedCharacters: allowed) ?? sectionType
        let query = buildQuery([
            ("userId", client.userId),
            ("additionalData", additionalData),
        ])
        return try await client.request("/HomeScreen/Section/\(encodedSection)", queryItems: query)
    }
}

struct JellyfinKefinTweaksApi: ServerKefinTweaksApi {
    let client: HttpClient

    private static let endpoints = [
        "/JavaScriptInjector/private.js",
        "/JavaScriptInjector/public.js",
    ]

    func fetchConfig() async throws -> KefinTweaksConfig? {
        var jsContent: String?

        for endpoint in Self.endpoints {
            guard let data = try? await client.requestData(endpoint) else {
                continue
            }
            guard let body = String(data: data, encoding: .utf8), !body.isEmpty else {
                continue
            }
            jsContent = body
            break
        }

        guard let jsContent else {
            return nil
        }

        if let strictObject = extractStrictConfigAssignment(from: jsContent),
           let config = decodeConfig(from: strictObject) {
            return config
        }

        guard let objectLiteral = extractConfigObject(from: jsContent) else {
            return nil
        }

        if let config = decodeConfig(from: objectLiteral) {
            return config
        }

        guard let normalized = normalizeJsObjectLiteral(objectLiteral),
              let config = decodeConfig(from: normalized) else {
            return nil
        }

        return config
    }

    private func decodeConfig(from jsonObjectText: String) -> KefinTweaksConfig? {
        guard let data = jsonObjectText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return KefinTweaksConfig(json: object)
    }

    private func extractStrictConfigAssignment(from source: String) -> String? {
        let pattern = #"window\.KefinTweaksConfig\s*=\s*({[\s\S]*?});"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)
        guard let match = regex.firstMatch(in: source, range: fullRange),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let objectRange = match.range(at: 1)
        guard objectRange.location != NSNotFound else {
            return nil
        }
        return nsSource.substring(with: objectRange)
    }

    private func extractConfigObject(from source: String) -> String? {
        let marker = "window.KefinTweaksConfig"
        var searchStart = source.startIndex

        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            guard let equalsIndex = source[markerRange.upperBound...].firstIndex(of: "=") else {
                return nil
            }

            guard let braceIndex = source[equalsIndex...].firstIndex(of: "{") else {
                return nil
            }

            if let closingBraceIndex = matchBrace(in: source, openIndex: braceIndex) {
                return String(source[braceIndex...closingBraceIndex])
            }

            searchStart = markerRange.upperBound
        }

        return nil
    }

    private func matchBrace(in source: String, openIndex: String.Index) -> String.Index? {
        var depth = 0
        var cursor = openIndex
        var inString = false
        var quote: Character?
        var isEscaping = false

        while cursor < source.endIndex {
            let character = source[cursor]

            if isEscaping {
                isEscaping = false
                cursor = source.index(after: cursor)
                continue
            }

            if inString {
                if character == "\\" {
                    isEscaping = true
                } else if character == quote {
                    inString = false
                    quote = nil
                }
                cursor = source.index(after: cursor)
                continue
            }

            if character == "\"" || character == "'" || character == "`" {
                inString = true
                quote = character
                cursor = source.index(after: cursor)
                continue
            }

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }

            cursor = source.index(after: cursor)
        }

        return nil
    }

    private func normalizeJsObjectLiteral(_ objectLiteral: String) -> String? {
        let context = JSContext()
        let script = """
        (function() {
          try {
            const __cfg = \(objectLiteral);
            return JSON.stringify(__cfg);
          } catch (e) {
            return null;
          }
        })();
        """

        return context?.evaluateScript(script)?.toString()
    }
}

// MARK: - Live TV

struct JellyfinLiveTvApi: ServerLiveTvApi {
    let client: HttpClient

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func getChannels(userId: String?, startIndex: Int?, limit: Int?, sortBy: String?, sortOrder: String?, isFavorite: Bool?, addCurrentProgram: Bool?) async throws -> ItemsResult {
        let query = buildQuery([
            ("UserId", userId),
            ("StartIndex", startIndex.map(String.init)),
            ("Limit", limit.map(String.init)),
            ("SortBy", sortBy),
            ("SortOrder", sortOrder),
            ("IsFavorite", isFavorite.map { String($0) }),
            ("AddCurrentProgram", addCurrentProgram.map { String($0) }),
            ("EnableFavoriteSorting", "true"),
        ])
        return try await client.request("/LiveTv/Channels", queryItems: query)
    }

    func getPrograms(channelIds: [String]?, userId: String?, startIndex: Int?, limit: Int?, minStartDate: Date?, maxStartDate: Date?, minEndDate: Date?, sortBy: String?) async throws -> ItemsResult {
        let query = buildQuery([
            ("ChannelIds", channelIds?.joined(separator: ",")),
            ("UserId", userId),
            ("StartIndex", startIndex.map(String.init)),
            ("Limit", limit.map(String.init)),
            ("MinStartDate", minStartDate.map { Self.dateFormatter.string(from: $0) }),
            ("MaxStartDate", maxStartDate.map { Self.dateFormatter.string(from: $0) }),
            ("MinEndDate", minEndDate.map { Self.dateFormatter.string(from: $0) }),
            ("SortBy", sortBy ?? "StartDate"),
            ("EnableImages", "false"),
        ])
        return try await client.request("/LiveTv/Programs", queryItems: query)
    }

    func getRecordings(channelId: String?, seriesTimerId: String?, startIndex: Int?, limit: Int?) async throws -> ItemsResult {
        let query = buildQuery([
            ("ChannelId", channelId),
            ("SeriesTimerId", seriesTimerId),
            ("StartIndex", startIndex.map(String.init)),
            ("Limit", limit.map(String.init)),
        ])
        return try await client.request("/LiveTv/Recordings", queryItems: query)
    }

    func getTimers(channelId: String?, seriesTimerId: String?) async throws -> [LiveTvTimerInfo] {
        struct TimersResult: Decodable { let Items: [LiveTvTimerInfo] }
        let query = buildQuery([
            ("ChannelId", channelId),
            ("SeriesTimerId", seriesTimerId),
        ])
        let result: TimersResult = try await client.request("/LiveTv/Timers", queryItems: query)
        return result.Items
    }

    func getSeriesTimers(sortBy: String?, startIndex: Int?, limit: Int?) async throws -> [LiveTvSeriesTimerInfo] {
        struct SeriesTimersResult: Decodable { let Items: [LiveTvSeriesTimerInfo] }
        let query = buildQuery([
            ("SortBy", sortBy),
            ("StartIndex", startIndex.map(String.init)),
            ("Limit", limit.map(String.init)),
        ])
        let result: SeriesTimersResult = try await client.request("/LiveTv/SeriesTimers", queryItems: query)
        return result.Items
    }

    func createTimer(_ timer: LiveTvTimerInfo) async throws {
        try await client.requestVoid("/LiveTv/Timers", body: timer)
    }

    func cancelTimer(timerId: String) async throws {
        try await client.requestVoid("/LiveTv/Timers/\(timerId)", method: "DELETE")
    }

    func cancelSeriesTimer(timerId: String) async throws {
        try await client.requestVoid("/LiveTv/SeriesTimers/\(timerId)", method: "DELETE")
    }

    func deleteRecording(recordingId: String) async throws {
        try await client.requestVoid("/Items/\(recordingId)", method: "DELETE")
    }

    func getRecommendedPrograms(userId: String?, limit: Int?, isAiring: Bool?, hasAired: Bool?) async throws -> ItemsResult {
        let query = buildQuery([
            ("UserId", userId),
            ("Limit", limit.map(String.init)),
            ("IsAiring", isAiring.map { String($0) }),
            ("HasAired", hasAired.map { String($0) }),
        ])
        return try await client.request("/LiveTv/Programs/Recommended", queryItems: query)
    }

    func getGuideInfo() async throws -> LiveTvGuideInfo {
        try await client.request("/LiveTv/GuideInfo")
    }
}

// MARK: - Instant Mix

struct JellyfinInstantMixApi: ServerInstantMixApi {
    let client: HttpClient

    func getInstantMix(itemId: String, userId: String?, limit: Int?) async throws -> ItemsResult {
        let query = buildQuery([
            ("UserId", userId ?? client.userId),
            ("Limit", limit.map(String.init)),
        ])
        return try await client.request("/Items/\(itemId)/InstantMix", queryItems: query)
    }
}

// MARK: - Playlist

struct JellyfinPlaylistApi: ServerPlaylistApi {
    let client: HttpClient

    func createPlaylist(name: String, itemIds: [String], mediaType: String?) async throws -> PlaylistCreationResult {
        let query = buildQuery([
            ("Name", name),
            ("Ids", itemIds.isEmpty ? nil : itemIds.joined(separator: ",")),
            ("MediaType", mediaType),
            ("UserId", client.userId),
        ])
        return try await client.request("/Playlists", method: "POST", queryItems: query)
    }

    func addToPlaylist(playlistId: String, itemIds: [String], userId: String?) async throws {
        let query = buildQuery([
            ("Ids", itemIds.joined(separator: ",")),
            ("UserId", userId ?? client.userId),
        ])
        try await client.requestVoid("/Playlists/\(playlistId)/Items", method: "POST", queryItems: query)
    }

    func moveItem(playlistId: String, itemId: String, newIndex: Int) async throws {
        try await client.requestVoid(
            "/Playlists/\(playlistId)/Items/\(itemId)/Move/\(newIndex)",
            method: "POST"
        )
    }

    func removeFromPlaylist(playlistId: String, entryIds: [String]) async throws {
        let query = buildQuery([
            ("EntryIds", entryIds.joined(separator: ",")),
        ])
        try await client.requestVoid("/Playlists/\(playlistId)/Items", method: "DELETE", queryItems: query)
    }

    func getPlaylists(userId: String) async throws -> ItemsResult {
        let query = buildQuery([
            ("IncludeItemTypes", "Playlist"),
            ("Recursive", "true"),
        ])
        return try await client.request("/Items", queryItems: query)
    }
}

// MARK: - Display Preferences

struct JellyfinDisplayPreferencesApi: ServerDisplayPreferencesApi {
    let client: HttpClient

    func getDisplayPreferences(id: String, userId: String, client: String) async throws -> DisplayPreferences {
        let query = buildQuery([
            ("UserId", userId),
            ("Client", client),
        ])
        return try await self.client.request("/DisplayPreferences/\(id)", queryItems: query)
    }

    func saveDisplayPreferences(id: String, userId: String, prefs: DisplayPreferences) async throws {
        let query = buildQuery([("UserId", userId)])
        try await client.requestVoid("/DisplayPreferences/\(id)", method: "POST", queryItems: query, body: prefs)
    }
}

struct JellyfinLyricsApi: ServerLyricsApi {
    let client: HttpClient

    func getLyrics(itemId: String) async throws -> LyricResult {
        try await client.request("/Audio/\(itemId)/Lyrics")
    }
}

struct JellyfinSyncPlayApi: ServerSyncPlayApi {
    let client: HttpClient

    func createGroup(groupName: String) async throws {
        struct Body: Encodable { let GroupName: String }
        try await client.requestVoid("/SyncPlay/New", method: "POST", body: Body(GroupName: groupName))
    }

    func joinGroup(groupId: String) async throws {
        struct Body: Encodable { let GroupId: String }
        try await client.requestVoid("/SyncPlay/Join", method: "POST", body: Body(GroupId: groupId))
    }

    func leaveGroup() async throws {
        try await client.requestVoid("/SyncPlay/Leave", method: "POST")
    }

    func getGroup(groupId: String) async throws -> SyncPlayGroupListItem {
        try await client.request("/SyncPlay/\(groupId)")
    }

    func getGroups() async throws -> [SyncPlayGroupListItem] {
        try await client.request("/SyncPlay/List")
    }

    func sendUnpause() async throws {
        try await client.requestVoid("/SyncPlay/Unpause", method: "POST")
    }

    func sendPause() async throws {
        try await client.requestVoid("/SyncPlay/Pause", method: "POST")
    }

    func sendSeek(positionTicks: Int64) async throws {
        struct Body: Encodable { let PositionTicks: Int64 }
        try await client.requestVoid("/SyncPlay/Seek", method: "POST", body: Body(PositionTicks: positionTicks))
    }

    func sendStop() async throws {
        try await client.requestVoid("/SyncPlay/Stop", method: "POST")
    }

    func sendBuffering(isPlaying: Bool, playlistItemId: String, positionTicks: Int64) async throws {
        struct Body: Encodable { let When: String; let PositionTicks: Int64; let IsPlaying: Bool; let PlaylistItemId: String }
        let when = ISO8601DateFormatter().string(from: Date())
        try await client.requestVoid("/SyncPlay/Buffering", method: "POST",
            body: Body(When: when, PositionTicks: positionTicks, IsPlaying: isPlaying, PlaylistItemId: playlistItemId))
    }

    func sendReady(isPlaying: Bool, playlistItemId: String, positionTicks: Int64) async throws {
        struct Body: Encodable { let When: String; let PositionTicks: Int64; let IsPlaying: Bool; let PlaylistItemId: String }
        let when = ISO8601DateFormatter().string(from: Date())
        try await client.requestVoid("/SyncPlay/Ready", method: "POST",
            body: Body(When: when, PositionTicks: positionTicks, IsPlaying: isPlaying, PlaylistItemId: playlistItemId))
    }

    func sendPing(ping: Int64) async throws {
        struct Body: Encodable { let Ping: Int64 }
        try await client.requestVoid("/SyncPlay/Ping", method: "POST", body: Body(Ping: ping))
    }

    func setNewQueue(itemIds: [String], startIndex: Int, startPositionTicks: Int64) async throws {
        struct Body: Encodable { let PlayingQueue: [String]; let PlayingItemPosition: Int; let StartPositionTicks: Int64 }
        try await client.requestVoid("/SyncPlay/SetNewQueue", method: "POST",
            body: Body(PlayingQueue: itemIds, PlayingItemPosition: startIndex, StartPositionTicks: startPositionTicks))
    }

    func setPlaylistItem(request: SyncPlaySetPlaylistItemRequest) async throws {
        try await client.requestVoid("/SyncPlay/SetPlaylistItem", method: "POST", body: request)
    }

    func removeFromPlaylist(request: SyncPlayRemoveFromPlaylistRequest) async throws {
        try await client.requestVoid("/SyncPlay/RemoveFromPlaylist", method: "POST", body: request)
    }

    func movePlaylistItem(request: SyncPlayMovePlaylistItemRequest) async throws {
        try await client.requestVoid("/SyncPlay/MovePlaylistItem", method: "POST", body: request)
    }

    func queue(request: SyncPlayQueueRequest) async throws {
        try await client.requestVoid("/SyncPlay/Queue", method: "POST", body: request)
    }

    func nextItem(request: SyncPlayPlaylistItemRequest) async throws {
        try await client.requestVoid("/SyncPlay/NextItem", method: "POST", body: request)
    }

    func previousItem(request: SyncPlayPlaylistItemRequest) async throws {
        try await client.requestVoid("/SyncPlay/PreviousItem", method: "POST", body: request)
    }

    func setRepeatMode(request: SyncPlaySetRepeatModeRequest) async throws {
        try await client.requestVoid("/SyncPlay/SetRepeatMode", method: "POST", body: request)
    }

    func setShuffleMode(request: SyncPlaySetShuffleModeRequest) async throws {
        try await client.requestVoid("/SyncPlay/SetShuffleMode", method: "POST", body: request)
    }

    func setIgnoreWait(request: SyncPlaySetIgnoreWaitRequest) async throws {
        try await client.requestVoid("/SyncPlay/SetIgnoreWait", method: "POST", body: request)
    }

    func getUtcTime() async throws -> UtcTimeResponse {
        try await client.request("/GetUtcTime")
    }
}
