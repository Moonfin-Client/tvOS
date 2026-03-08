import Foundation

final class EmbyServerClient: MediaServerClient {
    let serverType: ServerType = .emby
    let httpClient: HttpClient

    var baseURL: URL? { httpClient.baseURL }
    var accessToken: String? { httpClient.accessToken }
    var userId: String? { httpClient.userId }

    init(httpClient: HttpClient? = nil) {
        self.httpClient = httpClient ?? HttpClient(authFormat: .emby)
    }

    func configure(baseURL: URL, accessToken: String? = nil, userId: String? = nil) {
        httpClient.configure(baseURL: baseURL, accessToken: accessToken, userId: userId)
    }

    var authApi: ServerAuthApi { EmbyAuthApi(client: httpClient) }
    var itemsApi: ServerItemsApi { EmbyItemsApi(client: httpClient) }
    var userLibraryApi: ServerUserLibraryApi { EmbyUserLibraryApi(client: httpClient) }
    var playbackApi: ServerPlaybackApi { EmbyPlaybackApi(client: httpClient) }
    var sessionApi: ServerSessionApi { EmbySessionApi(client: httpClient) }
    var imageApi: ServerImageApi { EmbyImageApi(client: httpClient) }
    var systemApi: ServerSystemApi { EmbySystemApi(client: httpClient) }
    var userViewsApi: ServerUserViewsApi { EmbyUserViewsApi(client: httpClient) }
    var liveTvApi: ServerLiveTvApi { EmbyLiveTvApi(client: httpClient) }
    var instantMixApi: ServerInstantMixApi { EmbyInstantMixApi(client: httpClient) }
    var playlistApi: ServerPlaylistApi { EmbyPlaylistApi(client: httpClient) }
    var displayPreferencesApi: ServerDisplayPreferencesApi { EmbyDisplayPreferencesApi(client: httpClient) }
}
