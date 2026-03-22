import Foundation

final class Indirect<T: Codable>: Codable {
    let value: T
    init(_ value: T) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(T.self)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct NameIdPair: Codable, Hashable {
    let name: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

struct UserItemData: Codable {
    let playedPercentage: Double?
    let unplayedItemCount: Int?
    let playbackPositionTicks: Int64
    let playCount: Int
    let isFavorite: Bool
    let lastPlayedDate: Date?
    let played: Bool
    let key: String
    let itemId: String?

    enum CodingKeys: String, CodingKey {
        case playedPercentage = "PlayedPercentage"
        case unplayedItemCount = "UnplayedItemCount"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case isFavorite = "IsFavorite"
        case lastPlayedDate = "LastPlayedDate"
        case played = "Played"
        case key = "Key"
        case itemId = "ItemId"
    }
}

struct ServerChapter: Codable, Identifiable {
    var id: Int64 { startPositionTicks }
    let startPositionTicks: Int64
    let name: String?
    let imageTag: String?

    enum CodingKeys: String, CodingKey {
        case startPositionTicks = "StartPositionTicks"
        case name = "Name"
        case imageTag = "ImageTag"
    }
}

struct ServerPerson: Codable {
    let id: String?
    let name: String
    let role: String?
    let type: PersonType
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case role = "Role"
        case type = "Type"
        case primaryImageTag = "PrimaryImageTag"
    }
}

struct ServerMediaStream: Codable {
    let index: Int
    let type: StreamType
    let codec: String?
    let language: String?
    let displayTitle: String?
    let isDefault: Bool
    let isForced: Bool
    let isExternal: Bool
    let path: String?
    let width: Int?
    let height: Int?
    let channels: Int?
    let sampleRate: Int?
    let bitRate: Int?
    let bitDepth: Int?
    let isTextSubtitleStream: Bool
    let deliveryUrl: String?
    let profile: String?
    let level: Double?
    let realFrameRate: Float?
    let videoRange: String?
    let videoRangeType: String?
    let channelLayout: String?

    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case codec = "Codec"
        case language = "Language"
        case displayTitle = "DisplayTitle"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case isExternal = "IsExternal"
        case path = "Path"
        case width = "Width"
        case height = "Height"
        case channels = "Channels"
        case sampleRate = "SampleRate"
        case bitRate = "BitRate"
        case bitDepth = "BitDepth"
        case isTextSubtitleStream = "IsTextSubtitleStream"
        case deliveryUrl = "DeliveryUrl"
        case profile = "Profile"
        case level = "Level"
        case realFrameRate = "RealFrameRate"
        case videoRange = "VideoRange"
        case videoRangeType = "VideoRangeType"
        case channelLayout = "ChannelLayout"
    }
}

struct ServerMediaSource: Codable {
    let id: String
    let name: String?
    let container: String?
    let `protocol`: MediaProtocol
    let supportsDirectPlay: Bool
    let supportsDirectStream: Bool
    let supportsTranscoding: Bool
    let transcodingUrl: String?
    let eTag: String?
    let liveStreamId: String?
    let isRemote: Bool
    let bitrate: Int?
    let mediaStreams: [ServerMediaStream]
    let defaultAudioStreamIndex: Int?
    let defaultSubtitleStreamIndex: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case container = "Container"
        case `protocol` = "Protocol"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingUrl = "TranscodingUrl"
        case eTag = "ETag"
        case liveStreamId = "LiveStreamId"
        case isRemote = "IsRemote"
        case bitrate = "Bitrate"
        case mediaStreams = "MediaStreams"
        case defaultAudioStreamIndex = "DefaultAudioStreamIndex"
        case defaultSubtitleStreamIndex = "DefaultSubtitleStreamIndex"
    }
}

struct ServerItem: Codable, Identifiable {
    let id: String
    let serverId: String?
    var overrideServerId: String?
    let name: String
    let originalTitle: String?
    let type: ItemType
    let mediaType: MediaType?
    let overview: String?
    let runTimeTicks: Int64?
    let premiereDate: Date?
    let productionYear: Int?
    let officialRating: String?
    let communityRating: Double?
    let criticRating: Double?
    let isFolder: Bool?
    let parentId: String?
    let seriesId: String?
    let seriesName: String?
    let seasonId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let parentBackdropImageTags: [String]?
    let parentBackdropItemId: String?
    let primaryImageAspectRatio: Double?
    let userData: UserItemData?
    let mediaSources: [ServerMediaSource]?
    let mediaStreams: [ServerMediaStream]?
    let container: String?
    let channelId: String?
    let channelName: String?
    let collectionType: String?
    let people: [ServerPerson]?
    let chapters: [ServerChapter]?
    let genres: [String]?
    let tags: [String]?
    let taglines: [String]?
    let studios: [NameIdPair]?
    let providerIds: [String: String]?
    let endDate: Date?
    let productionLocations: [String]?
    let artists: [String]?
    let albumArtists: [NameIdPair]?
    let albumArtist: String?
    let albumId: String?
    let albumPrimaryImageTag: String?
    let album: String?
    let childCount: Int?
    let albumCount: Int?
    let hasLyrics: Bool?
    let dateCreated: Date?
    let playlistItemId: String?
    let canDelete: Bool?
    let localTrailerCount: Int?
    let remoteTrailers: [MediaUrl]?

    let startDate: Date?
    let channelNumber: String?
    let timerId: String?
    let seriesTimerId: String?
    let isMovie: Bool?
    let isSeries: Bool?
    let isNews: Bool?
    let isSports: Bool?
    let isKids: Bool?
    let isPremiere: Bool?
    let isRepeat: Bool?
    let isLive: Bool?
    let isHD: Bool?
    let status: String?
    let currentProgram: Indirect<ServerItem>?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverId = "ServerId"
        case name = "Name"
        case originalTitle = "OriginalTitle"
        case type = "Type"
        case mediaType = "MediaType"
        case overview = "Overview"
        case runTimeTicks = "RunTimeTicks"
        case premiereDate = "PremiereDate"
        case productionYear = "ProductionYear"
        case officialRating = "OfficialRating"
        case communityRating = "CommunityRating"
        case criticRating = "CriticRating"
        case isFolder = "IsFolder"
        case parentId = "ParentId"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case seasonId = "SeasonId"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case parentBackdropItemId = "ParentBackdropItemId"
        case primaryImageAspectRatio = "PrimaryImageAspectRatio"
        case userData = "UserData"
        case mediaSources = "MediaSources"
        case mediaStreams = "MediaStreams"
        case container = "Container"
        case channelId = "ChannelId"
        case channelName = "ChannelName"
        case collectionType = "CollectionType"
        case people = "People"
        case chapters = "Chapters"
        case genres = "Genres"
        case tags = "Tags"
        case taglines = "Taglines"
        case studios = "Studios"
        case providerIds = "ProviderIds"
        case endDate = "EndDate"
        case productionLocations = "ProductionLocations"
        case artists = "Artists"
        case albumArtists = "AlbumArtists"
        case albumArtist = "AlbumArtist"
        case albumId = "AlbumId"
        case albumPrimaryImageTag = "AlbumPrimaryImageTag"
        case album = "Album"
        case childCount = "ChildCount"
        case albumCount = "AlbumCount"
        case hasLyrics = "HasLyrics"
        case dateCreated = "DateCreated"
        case playlistItemId = "PlaylistItemId"
        case canDelete = "CanDelete"
        case localTrailerCount = "LocalTrailerCount"
        case remoteTrailers = "RemoteTrailers"
        case startDate = "StartDate"
        case channelNumber = "ChannelNumber"
        case timerId = "TimerId"
        case seriesTimerId = "SeriesTimerId"
        case isMovie = "IsMovie"
        case isSeries = "IsSeries"
        case isNews = "IsNews"
        case isSports = "IsSports"
        case isKids = "IsKids"
        case isPremiere = "IsPremiere"
        case isRepeat = "IsRepeat"
        case isLive = "IsLive"
        case isHD = "IsHD"
        case status = "Status"
        case currentProgram = "CurrentProgram"
    }
}

extension ServerItem {
    var effectiveServerId: String? { overrideServerId ?? serverId }

    static func placeholder(id: String, name: String, type: ItemType = .folder) -> ServerItem {
        ServerItem(
            id: id, serverId: nil, name: name, originalTitle: nil, type: type, mediaType: nil,
            overview: nil, runTimeTicks: nil, premiereDate: nil, productionYear: nil,
            officialRating: nil, communityRating: nil, criticRating: nil, isFolder: nil,
            parentId: nil, seriesId: nil, seriesName: nil, seasonId: nil, indexNumber: nil,
            parentIndexNumber: nil, imageTags: nil, backdropImageTags: nil,
            parentBackdropImageTags: nil, parentBackdropItemId: nil,
            primaryImageAspectRatio: nil, userData: nil, mediaSources: nil,
            mediaStreams: nil, container: nil, channelId: nil, channelName: nil,
            collectionType: nil, people: nil, chapters: nil, genres: nil, tags: nil,
            taglines: nil, studios: nil, providerIds: nil, endDate: nil,
            productionLocations: nil, artists: nil, albumArtists: nil, albumArtist: nil,
            albumId: nil, albumPrimaryImageTag: nil, album: nil, childCount: nil,
            albumCount: nil, hasLyrics: nil, dateCreated: nil, playlistItemId: nil, canDelete: nil, localTrailerCount: nil, remoteTrailers: nil, startDate: nil, channelNumber: nil,
            timerId: nil, seriesTimerId: nil, isMovie: nil, isSeries: nil, isNews: nil,
            isSports: nil, isKids: nil, isPremiere: nil, isRepeat: nil, isLive: nil,
            isHD: nil, status: nil, currentProgram: nil
        )
    }
}

struct ServerUser: Codable {
    let id: String
    let name: String
    let serverName: String?
    let primaryImageTag: String?
    let hasPassword: Bool?
    let hasConfiguredPassword: Bool?
    let lastLoginDate: Date?
    let lastActivityDate: Date?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case serverName = "ServerName"
        case primaryImageTag = "PrimaryImageTag"
        case hasPassword = "HasPassword"
        case hasConfiguredPassword = "HasConfiguredPassword"
        case lastLoginDate = "LastLoginDate"
        case lastActivityDate = "LastActivityDate"
    }
}

struct ItemsResult: Codable {
    let items: [ServerItem]
    let totalRecordCount: Int
    let startIndex: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }

    init(items: [ServerItem] = [], totalRecordCount: Int = 0, startIndex: Int = 0) {
        self.items = items
        self.totalRecordCount = totalRecordCount
        self.startIndex = startIndex
    }
}

struct AllThemeMediaResult: Codable {
    let themeSongsResult: ItemsResult
    let themeVideosResult: ItemsResult

    enum CodingKeys: String, CodingKey {
        case themeSongsResult = "ThemeSongsResult"
        case themeVideosResult = "ThemeVideosResult"
    }
}

struct MediaUrl: Codable {
    let url: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case url = "Url"
        case name = "Name"
    }
}
