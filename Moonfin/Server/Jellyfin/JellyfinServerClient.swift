import Foundation

final class JellyfinServerClient: MediaServerClient {
    let serverType: ServerType = .jellyfin
    let httpClient: HttpClient
    private let _webSocketClient: ServerWebSocketClient

    var baseURL: URL? { httpClient.baseURL }
    var accessToken: String? { httpClient.accessToken }
    var userId: String? { httpClient.userId }

    init(httpClient: HttpClient? = nil) {
        let client = httpClient ?? HttpClient(authFormat: .jellyfin)
        self.httpClient = client
        self._webSocketClient = ServerWebSocketClient(serverType: .jellyfin, httpClient: client)
    }

    func configure(baseURL: URL, accessToken: String? = nil, userId: String? = nil) {
        httpClient.configure(baseURL: baseURL, accessToken: accessToken, userId: userId)
    }

    var webSocketApi: ServerWebSocketApi { _webSocketClient }
    var authApi: ServerAuthApi { JellyfinAuthApi(client: httpClient) }
    var itemsApi: ServerItemsApi { JellyfinItemsApi(client: httpClient) }
    var userLibraryApi: ServerUserLibraryApi { JellyfinUserLibraryApi(client: httpClient) }
    var playbackApi: ServerPlaybackApi { JellyfinPlaybackApi(client: httpClient) }
    var sessionApi: ServerSessionApi { JellyfinSessionApi(client: httpClient) }
    var imageApi: ServerImageApi { JellyfinImageApi(client: httpClient) }
    var systemApi: ServerSystemApi { JellyfinSystemApi(client: httpClient) }
    var userViewsApi: ServerUserViewsApi { JellyfinUserViewsApi(client: httpClient) }
    var adminPluginsApi: ServerAdminPluginsApi? { JellyfinAdminPluginsApi(client: httpClient) }
    var homeScreenSectionsApi: ServerHomeScreenSectionsApi? { JellyfinHomeScreenSectionsApi(client: httpClient) }
    var kefinTweaksApi: ServerKefinTweaksApi? { JellyfinKefinTweaksApi(client: httpClient) }
    var liveTvApi: ServerLiveTvApi { JellyfinLiveTvApi(client: httpClient) }
    var instantMixApi: ServerInstantMixApi { JellyfinInstantMixApi(client: httpClient) }
    var playlistApi: ServerPlaylistApi { JellyfinPlaylistApi(client: httpClient) }
    var displayPreferencesApi: ServerDisplayPreferencesApi { JellyfinDisplayPreferencesApi(client: httpClient) }
    var lyricsApi: ServerLyricsApi { JellyfinLyricsApi(client: httpClient) }
    var syncPlayApi: ServerSyncPlayApi { JellyfinSyncPlayApi(client: httpClient) }
}
