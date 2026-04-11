import Foundation

enum Destination: Hashable {

    // MARK: - Startup

    case serverAdd
    case embyConnect
    case serverUsers(serverId: UUID)
    case userLogin(serverId: UUID, username: String?)
    case connectHelp

    // MARK: - Home

    case home

    // MARK: - Search

    case search(query: String? = nil)

    // MARK: - Library Browsing

    case libraryBrowser(itemId: String, parentId: String? = nil, serverId: String? = nil, userId: String? = nil)
    case libraryBrowserByType(itemId: String, includeType: String)
    case liveTvBrowser(itemId: String)
    case musicBrowser(itemId: String, serverId: String? = nil, userId: String? = nil)
    case collectionBrowser(itemId: String, serverId: String? = nil, userId: String? = nil)
    case folderBrowser(itemId: String, serverId: String? = nil, userId: String? = nil)
    case allGenres
    case allFavorites
    case folderView
    case genreBrowse(genreName: String, parentId: String? = nil, includeType: String? = nil, serverId: String? = nil)
    case libraryByGenres(itemId: String, includeType: String)
    case libraryByLetter(itemId: String, includeType: String)
    case librarySuggestions(itemId: String)

    // MARK: - Item Details

    case itemDetails(itemId: String, serverId: String? = nil)
    case channelDetails(itemId: String, channelId: String)
    case seriesTimerDetails(itemId: String)
    case itemList(itemId: String, serverId: String? = nil)
    case musicFavorites(parentId: String)

    // MARK: - Live TV

    case liveTvGuide
    case liveTvSchedule
    case liveTvRecordings
    case liveTvSeriesRecordings
    case liveTvPlayer(channelId: String)

    // MARK: - Playback

    case nowPlaying
    case photoPlayer(itemId: String, autoPlay: Bool, sortBy: String? = nil, sortOrder: String? = nil)
    case bookReader(itemId: String, serverId: String? = nil)
    case videoPlayer
    case nextUp(itemId: String)
    case stillWatching(itemId: String)
    case trailerPlayer(videoId: String? = nil, trailerUrl: String? = nil, startSeconds: Double = 0, segmentsJson: String = "[]")

    // MARK: - Seerr

    case seerrDiscover
    case seerrRequests
    case seerrSettings
    case seerrBrowseBy(filterId: Int, filterName: String, mediaType: String, filterType: String = "genre")
    case seerrMediaDetails(itemJson: String)
    case seerrPersonDetails(personId: Int)
}
