import Foundation

protocol MediaServerClient: AnyObject {
    var serverType: ServerType { get }
    var baseURL: URL? { get }
    var accessToken: String? { get }
    var userId: String? { get }
    var isUsable: Bool { get }
    var httpClient: HttpClient { get }

    func configure(baseURL: URL, accessToken: String?, userId: String?)

    var authApi: ServerAuthApi { get }
    var itemsApi: ServerItemsApi { get }
    var userLibraryApi: ServerUserLibraryApi { get }
    var playbackApi: ServerPlaybackApi { get }
    var sessionApi: ServerSessionApi { get }
    var imageApi: ServerImageApi { get }
    var systemApi: ServerSystemApi { get }
    var userViewsApi: ServerUserViewsApi { get }
    var liveTvApi: ServerLiveTvApi { get }
    var instantMixApi: ServerInstantMixApi { get }
    var playlistApi: ServerPlaylistApi { get }
    var displayPreferencesApi: ServerDisplayPreferencesApi { get }
    var lyricsApi: ServerLyricsApi { get }
    var syncPlayApi: ServerSyncPlayApi { get }
}

extension MediaServerClient {
    var isUsable: Bool { baseURL != nil && accessToken != nil }
}

// MARK: - Auth

protocol ServerAuthApi {
    func authenticateByName(username: String, password: String) async throws -> AuthResult
    func getCurrentUser() async throws -> ServerUser
    func getPublicUsers() async throws -> [ServerUser]
    func logout() async throws
    func supportsQuickConnect() async throws -> Bool
    func initiateQuickConnect() async throws -> QuickConnectInfo?
    func checkQuickConnectStatus(secret: String) async throws -> Bool
    func authenticateWithQuickConnect(secret: String) async throws -> AuthResult
}

// MARK: - System

protocol ServerSystemApi {
    func getPublicSystemInfo() async throws -> PublicSystemInfo
    func getSystemInfo() async throws -> SystemInfo
}

// MARK: - Items

protocol ServerItemsApi {
    func getItems(request: GetItemsRequest) async throws -> ItemsResult
    func getResumeItems(request: GetResumeItemsRequest) async throws -> ItemsResult
    func getLatestMedia(request: GetLatestMediaRequest) async throws -> [ServerItem]
    func getNextUp(request: GetNextUpRequest) async throws -> ItemsResult
    func getSimilarItems(itemId: String, limit: Int?) async throws -> ItemsResult
    func getSeasons(seriesId: String, userId: String) async throws -> ItemsResult
    func getEpisodes(seriesId: String, seasonId: String, userId: String) async throws -> ItemsResult
}

// MARK: - User Library

protocol ServerUserLibraryApi {
    func getItem(itemId: String) async throws -> ServerItem
    func getSpecialFeatures(itemId: String) async throws -> [ServerItem]
    func getThemeMedia(itemId: String, userId: String, inheritFromParent: Bool) async throws -> AllThemeMediaResult
    func getIntros(itemId: String) async throws -> [ServerItem]
    func markFavorite(itemId: String, userId: String) async throws -> UserItemData
    func unmarkFavorite(itemId: String, userId: String) async throws -> UserItemData
    func markPlayed(itemId: String, userId: String) async throws -> UserItemData
    func unmarkPlayed(itemId: String, userId: String) async throws -> UserItemData
}

// MARK: - Playback

protocol ServerPlaybackApi {
    func getPlaybackInfo(itemId: String, request: PlaybackInfoRequest) async throws -> PlaybackInfoResult
    func getVideoStreamUrl(itemId: String, params: StreamParams) -> String
    func getAudioStreamUrl(itemId: String, params: StreamParams) -> String
    func reportPlaybackStart(info: PlaybackStartReport) async throws
    func reportPlaybackProgress(info: PlaybackProgressReport) async throws
    func reportPlaybackStopped(info: PlaybackStopReport) async throws
}

// MARK: - Image

protocol ServerImageApi {
    func getItemImageUrl(itemId: String, imageType: ImageType, maxWidth: Int?, maxHeight: Int?, tag: String?) -> String
    func getChapterImageUrl(itemId: String, chapterIndex: Int, maxWidth: Int?, tag: String?) -> String
    func getUserImageUrl(userId: String, imageType: ImageType, tag: String?) -> String
}

// MARK: - Session

protocol ServerSessionApi {
    func postCapabilities(_ capabilities: ClientCapabilities) async throws
    func getSessions() async throws -> [SessionInfo]
}

// MARK: - User Views

protocol ServerUserViewsApi {
    func getUserViews(userId: String) async throws -> [ServerItem]
}

// MARK: - Live TV

protocol ServerLiveTvApi {
    func getChannels(userId: String?, startIndex: Int?, limit: Int?, sortBy: String?, sortOrder: String?, isFavorite: Bool?, addCurrentProgram: Bool?) async throws -> ItemsResult
    func getPrograms(channelIds: [String]?, userId: String?, startIndex: Int?, limit: Int?, minStartDate: Date?, maxStartDate: Date?, minEndDate: Date?, sortBy: String?) async throws -> ItemsResult
    func getRecordings(channelId: String?, seriesTimerId: String?, startIndex: Int?, limit: Int?) async throws -> ItemsResult
    func getTimers(channelId: String?, seriesTimerId: String?) async throws -> [LiveTvTimerInfo]
    func getSeriesTimers(sortBy: String?, startIndex: Int?, limit: Int?) async throws -> [LiveTvSeriesTimerInfo]
    func createTimer(_ timer: LiveTvTimerInfo) async throws
    func cancelTimer(timerId: String) async throws
    func cancelSeriesTimer(timerId: String) async throws
    func deleteRecording(recordingId: String) async throws
    func getRecommendedPrograms(userId: String?, limit: Int?, isAiring: Bool?, hasAired: Bool?) async throws -> ItemsResult
    func getGuideInfo() async throws -> LiveTvGuideInfo
}

// MARK: - Instant Mix

protocol ServerInstantMixApi {
    func getInstantMix(itemId: String, userId: String?, limit: Int?) async throws -> ItemsResult
}

// MARK: - Playlist

struct PlaylistCreationResult: Codable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}

protocol ServerPlaylistApi {
    func createPlaylist(name: String, itemIds: [String], mediaType: String?) async throws -> PlaylistCreationResult
    func addToPlaylist(playlistId: String, itemIds: [String], userId: String?) async throws
    func removeFromPlaylist(playlistId: String, entryIds: [String]) async throws
    func getPlaylists(userId: String) async throws -> ItemsResult
}

// MARK: - Display Preferences

protocol ServerDisplayPreferencesApi {
    func getDisplayPreferences(id: String, userId: String, client: String) async throws -> DisplayPreferences
    func saveDisplayPreferences(id: String, userId: String, prefs: DisplayPreferences) async throws
}

// MARK: - Lyrics

struct LyricLine: Codable {
    let text: String
    let start: Int64?

    enum CodingKeys: String, CodingKey {
        case text = "Text"
        case start = "Start"
    }
}

struct LyricResult: Codable {
    let lyrics: [LyricLine]

    enum CodingKeys: String, CodingKey {
        case lyrics = "Lyrics"
    }
}

protocol ServerLyricsApi {
    func getLyrics(itemId: String) async throws -> LyricResult
}

// MARK: - SyncPlay

struct SyncPlayGroupListItem: Codable {
    let groupId: String
    let groupName: String
    let state: String
    let participants: [String]
    let lastUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case groupId = "GroupId"
        case groupName = "GroupName"
        case state = "State"
        case participants = "Participants"
        case lastUpdatedAt = "LastUpdatedAt"
    }
}

protocol ServerSyncPlayApi {
    func createGroup(groupName: String) async throws
    func joinGroup(groupId: String) async throws
    func leaveGroup() async throws
    func getGroups() async throws -> [SyncPlayGroupListItem]
    func sendUnpause() async throws
    func sendPause() async throws
    func sendSeek(positionTicks: Int64) async throws
    func sendStop() async throws
    func sendBuffering(isPlaying: Bool, itemId: String, positionTicks: Int64) async throws
    func sendReady(isPlaying: Bool, itemId: String, positionTicks: Int64) async throws
    func sendPing(ping: Int64) async throws
    func setNewQueue(itemIds: [String], startIndex: Int, startPositionTicks: Int64) async throws
    func getUtcTime() async throws -> UtcTimeResponse
}

struct UtcTimeResponse: Decodable {
    let requestReceptionTime: String
    let responseTransmissionTime: String

    enum CodingKeys: String, CodingKey {
        case requestReceptionTime = "RequestReceptionTime"
        case responseTransmissionTime = "ResponseTransmissionTime"
    }
}

// MARK: - WebSocket

protocol ServerWebSocketApi {
    func connect() async throws
    func disconnect() async
    var onMessage: ((ServerWebSocketMessage) -> Void)? { get set }
}
