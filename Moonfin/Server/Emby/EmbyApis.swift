import Foundation

// MARK: - Auth

struct EmbyAuthApi: ServerAuthApi {
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
        let userId = client.userId ?? ""
        return try await client.request("/Users/\(userId)")
    }

    func getPublicUsers() async throws -> [ServerUser] {
        try await client.request("/Users/Public")
    }

    func logout() async throws {
        try await client.requestVoid("/Sessions/Logout")
    }

    func supportsQuickConnect() async throws -> Bool {
        false
    }

    func initiateQuickConnect() async throws -> QuickConnectInfo? {
        throw ServerError.unsupported("QuickConnect is not supported on Emby")
    }

    func checkQuickConnectStatus(secret: String) async throws -> Bool {
        throw ServerError.unsupported("QuickConnect is not supported on Emby")
    }

    func authenticateWithQuickConnect(secret: String) async throws -> AuthResult {
        throw ServerError.unsupported("QuickConnect is not supported on Emby")
    }
}

// MARK: - System

struct EmbySystemApi: ServerSystemApi {
    let client: HttpClient

    func getPublicSystemInfo() async throws -> PublicSystemInfo {
        try await client.request("/System/Info/Public")
    }

    func getSystemInfo() async throws -> SystemInfo {
        try await client.request("/System/Info")
    }
}

// MARK: - Items

struct EmbyItemsApi: ServerItemsApi {
    let client: HttpClient

    func getItems(request: GetItemsRequest) async throws -> ItemsResult {
        let userId = request.userId ?? client.userId
        let path = userId != nil ? "/Users/\(userId!)/Items" : "/Items"
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
            ("Tags", request.tags?.joined(separator: ",")),
            ("Years", request.years?.map(String.init).joined(separator: ",")),
            ("Ids", request.ids?.joined(separator: ",")),
            ("EnableImages", request.enableImages.map(String.init)),
            ("ImageTypeLimit", request.imageTypeLimit.map(String.init)),
            ("EnableUserData", request.enableUserData.map(String.init)),
            ("GroupItemsIntoCollections", request.groupItems.map(String.init)),
        ])
        return try await client.request(path, queryItems: query)
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
        ])
        return try await client.request("/Shows/\(seriesId)/Episodes", queryItems: query)
    }
}

// MARK: - User Library

struct EmbyUserLibraryApi: ServerUserLibraryApi {
    let client: HttpClient

    func getItem(itemId: String) async throws -> ServerItem {
        let userId = client.userId ?? ""
        return try await client.request("/Users/\(userId)/Items/\(itemId)")
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

struct EmbyPlaybackApi: ServerPlaybackApi {
    let client: HttpClient

    func getPlaybackInfo(itemId: String, request: PlaybackInfoRequest) async throws -> PlaybackInfoResult {
        try await client.request("/Items/\(itemId)/PlaybackInfo", method: "POST", body: request)
    }

    func getVideoStreamUrl(itemId: String, params: StreamParams) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        var url = "\(base)/Videos/\(itemId)/stream.\(params.container)"
        url += "?Static=true"
        url += "&MediaSourceId=\(params.mediaSourceId)"
        url += "&PlaySessionId=\(params.playSessionId)"
        url += "&DeviceId=\(params.deviceId)"
        if let idx = params.audioStreamIndex { url += "&AudioStreamIndex=\(idx)" }
        if let idx = params.subtitleStreamIndex { url += "&SubtitleStreamIndex=\(idx)" }
        if let token = client.accessToken { url += "&api_key=\(token)" }
        return url
    }

    func getAudioStreamUrl(itemId: String, params: StreamParams) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        var url = "\(base)/Audio/\(itemId)/stream.\(params.container)"
        url += "?Static=true"
        url += "&MediaSourceId=\(params.mediaSourceId)"
        url += "&PlaySessionId=\(params.playSessionId)"
        url += "&DeviceId=\(params.deviceId)"
        if let token = client.accessToken { url += "&api_key=\(token)" }
        return url
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

struct EmbyImageApi: ServerImageApi {
    let client: HttpClient

    func getItemImageUrl(itemId: String, imageType: ImageType, maxWidth: Int?, maxHeight: Int?, tag: String?) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        var params: [String] = []
        if let w = maxWidth { params.append("maxWidth=\(w)") }
        if let h = maxHeight { params.append("maxHeight=\(h)") }
        if let t = tag { params.append("tag=\(t)") }
        if let token = client.accessToken { params.append("api_key=\(token)") }
        let path = "\(base)/Items/\(itemId)/Images/\(imageType.rawValue)"
        return params.isEmpty ? path : "\(path)?\(params.joined(separator: "&"))"
    }

    func getUserImageUrl(userId: String, imageType: ImageType, tag: String?) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        var params: [String] = []
        if let t = tag { params.append("tag=\(t)") }
        if let token = client.accessToken { params.append("api_key=\(token)") }
        let path = "\(base)/Users/\(userId)/Images/\(imageType.rawValue)"
        return params.isEmpty ? path : "\(path)?\(params.joined(separator: "&"))"
    }
}

// MARK: - Session

struct EmbySessionApi: ServerSessionApi {
    let client: HttpClient

    func postCapabilities(_ capabilities: ClientCapabilities) async throws {
        try await client.requestVoid("/Sessions/Capabilities/Full", body: capabilities)
    }

    func getSessions() async throws -> [SessionInfo] {
        try await client.request("/Sessions")
    }
}

// MARK: - User Views

struct EmbyUserViewsApi: ServerUserViewsApi {
    let client: HttpClient

    func getUserViews(userId: String) async throws -> [ServerItem] {
        struct ViewsResponse: Decodable { let Items: [ServerItem] }
        let response: ViewsResponse = try await client.request("/Users/\(userId)/Views")
        return response.Items
    }
}

// MARK: - Live TV

struct EmbyLiveTvApi: ServerLiveTvApi {
    let client: HttpClient

    func getChannels(userId: String?, startIndex: Int?, limit: Int?) async throws -> ItemsResult {
        let query = buildQuery([
            ("UserId", userId),
            ("StartIndex", startIndex.map(String.init)),
            ("Limit", limit.map(String.init)),
        ])
        return try await client.request("/LiveTv/Channels", queryItems: query)
    }

    func getPrograms(channelIds: [String]?, userId: String?, startIndex: Int?, limit: Int?) async throws -> ItemsResult {
        let query = buildQuery([
            ("ChannelIds", channelIds?.joined(separator: ",")),
            ("UserId", userId),
            ("StartIndex", startIndex.map(String.init)),
            ("Limit", limit.map(String.init)),
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

    func getRecommendedPrograms(userId: String?, limit: Int?) async throws -> ItemsResult {
        let query = buildQuery([
            ("UserId", userId),
            ("Limit", limit.map(String.init)),
        ])
        return try await client.request("/LiveTv/Programs/Recommended", queryItems: query)
    }

    func getGuideInfo() async throws -> LiveTvGuideInfo {
        try await client.request("/LiveTv/GuideInfo")
    }
}

// MARK: - Instant Mix

struct EmbyInstantMixApi: ServerInstantMixApi {
    let client: HttpClient

    func getInstantMix(itemId: String, userId: String?, limit: Int?) async throws -> ItemsResult {
        let query = buildQuery([
            ("UserId", userId ?? client.userId),
            ("Limit", limit.map(String.init)),
        ])
        return try await client.request("/Items/\(itemId)/InstantMix", queryItems: query)
    }
}

// MARK: - Display Preferences

struct EmbyDisplayPreferencesApi: ServerDisplayPreferencesApi {
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
