import Foundation

enum ItemType: String, Codable, CaseIterable {
    case movie, series, season, episode
    case audio, musicAlbum, musicArtist, musicVideo
    case playlist, photo, photoAlbum
    case boxSet, channel, program
    case recording, liveTvChannel, liveTvProgram
    case book, trailer, video
    case person, studio, genre, musicGenre
    case userView, collectionFolder, folder, basePluginFolder
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = ItemType(rawValue: value)
            ?? ItemType(rawValue: value.lowercased())
            ?? .unknown
    }
}

enum MediaType: String, Codable {
    case video = "Video"
    case audio = "Audio"
    case photo = "Photo"
    case book = "Book"
    case unknown = "Unknown"

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = MediaType(rawValue: value) ?? .unknown
    }
}

enum StreamType: String, Codable {
    case video = "Video"
    case audio = "Audio"
    case subtitle = "Subtitle"
    case embeddedImage = "EmbeddedImage"
    case attachment = "Attachment"
    case data = "Data"
}

enum PersonType: String, Codable {
    case actor = "Actor"
    case director = "Director"
    case writer = "Writer"
    case producer = "Producer"
    case guestStar = "GuestStar"
    case composer = "Composer"
    case conductor = "Conductor"
    case lyricist = "Lyricist"
    case unknown = "Unknown"

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = PersonType(rawValue: value) ?? .unknown
    }
}

enum ImageType: String, Codable, Hashable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case banner = "Banner"
    case thumb = "Thumb"
    case logo = "Logo"
    case art = "Art"
    case screenshot = "Screenshot"
}

enum PlayMethod: String, Codable {
    case directPlay = "DirectPlay"
    case directStream = "DirectStream"
    case transcode = "Transcode"
}

enum MediaProtocol: String, Codable {
    case file = "File"
    case http = "Http"
    case rtmp = "Rtmp"
    case rtsp = "Rtsp"
    case udp = "Udp"
    case rtp = "Rtp"
    case ftp = "Ftp"
}

enum PlaybackErrorCode: String, Codable {
    case notAllowed = "NotAllowed"
    case noCompatibleStream = "NoCompatibleStream"
    case rateLimitExceeded = "RateLimitExceeded"
}

enum ItemSortBy: String, Codable {
    case sortName = "SortName"
    case premiereDate = "PremiereDate"
    case dateCreated = "DateCreated"
    case datePlayed = "DatePlayed"
    case communityRating = "CommunityRating"
    case criticRating = "CriticRating"
    case runtime = "Runtime"
    case playCount = "PlayCount"
    case random = "Random"
    case officialRating = "OfficialRating"
    case indexNumber = "IndexNumber"
    case trackNumber = "TrackNumber"
    case album = "Album"
    case albumArtist = "AlbumArtist"
    case artist = "Artist"
}

enum SortOrder: String, Codable {
    case ascending = "Ascending"
    case descending = "Descending"
}

enum ItemFilter: String, Codable {
    case isPlayed = "IsPlayed"
    case isUnplayed = "IsUnplayed"
    case isFavorite = "IsFavorite"
    case isResumable = "IsResumable"
    case likes = "Likes"
    case dislikes = "Dislikes"
}

enum ItemField: String, Codable {
    case overview = "Overview"
    case genres = "Genres"
    case mediaSources = "MediaSources"
    case mediaStreams = "MediaStreams"
    case primaryImageAspectRatio = "PrimaryImageAspectRatio"
    case chapters = "Chapters"
    case childCount = "ChildCount"
    case dateCreated = "DateCreated"
    case channelInfo = "ChannelInfo"
    case canDelete = "CanDelete"
    case taglines = "Taglines"
    case providerIds = "ProviderIds"
    case displayPreferencesId = "DisplayPreferencesId"
    case itemCounts = "ItemCounts"
    case mediaSourceCount = "MediaSourceCount"
    case cumulativeRunTimeTicks = "CumulativeRunTimeTicks"
    case trickplay = "Trickplay"
    case path = "Path"
}
