import Foundation

struct PlaybackInfoRequest: Codable {
    let userId: String
    let mediaSourceId: String?
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let maxStreamingBitrate: Int64?
    let maxAudioChannels: Int?
    let startTimeTicks: Int64?
    let enableDirectPlay: Bool
    let enableDirectStream: Bool
    let enableTranscoding: Bool
    let allowVideoStreamCopy: Bool
    let allowAudioStreamCopy: Bool
    let autoOpenLiveStream: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "UserId"
        case mediaSourceId = "MediaSourceId"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case maxAudioChannels = "MaxAudioChannels"
        case startTimeTicks = "StartTimeTicks"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case allowVideoStreamCopy = "AllowVideoStreamCopy"
        case allowAudioStreamCopy = "AllowAudioStreamCopy"
        case autoOpenLiveStream = "AutoOpenLiveStream"
    }

    init(
        userId: String,
        mediaSourceId: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        maxStreamingBitrate: Int64? = nil,
        maxAudioChannels: Int? = nil,
        startTimeTicks: Int64? = nil,
        enableDirectPlay: Bool = true,
        enableDirectStream: Bool = true,
        enableTranscoding: Bool = true,
        allowVideoStreamCopy: Bool = true,
        allowAudioStreamCopy: Bool = true,
        autoOpenLiveStream: Bool = false
    ) {
        self.userId = userId
        self.mediaSourceId = mediaSourceId
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.maxStreamingBitrate = maxStreamingBitrate
        self.maxAudioChannels = maxAudioChannels
        self.startTimeTicks = startTimeTicks
        self.enableDirectPlay = enableDirectPlay
        self.enableDirectStream = enableDirectStream
        self.enableTranscoding = enableTranscoding
        self.allowVideoStreamCopy = allowVideoStreamCopy
        self.allowAudioStreamCopy = allowAudioStreamCopy
        self.autoOpenLiveStream = autoOpenLiveStream
    }
}

struct PlaybackInfoResult: Codable {
    let mediaSources: [ServerMediaSource]
    let playSessionId: String?
    let errorCode: PlaybackErrorCode?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
        case errorCode = "ErrorCode"
    }
}

struct PlaybackStartReport: Codable {
    let itemId: String
    let playSessionId: String
    let mediaSourceId: String
    let positionTicks: Int64
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let playMethod: PlayMethod
    let isPaused: Bool
    let isMuted: Bool
    let volumeLevel: Int

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case playSessionId = "PlaySessionId"
        case mediaSourceId = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case playMethod = "PlayMethod"
        case isPaused = "IsPaused"
        case isMuted = "IsMuted"
        case volumeLevel = "VolumeLevel"
    }
}

struct PlaybackProgressReport: Codable {
    let itemId: String
    let playSessionId: String
    let mediaSourceId: String
    let positionTicks: Int64
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let playMethod: PlayMethod
    let isPaused: Bool
    let isMuted: Bool
    let volumeLevel: Int

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case playSessionId = "PlaySessionId"
        case mediaSourceId = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case playMethod = "PlayMethod"
        case isPaused = "IsPaused"
        case isMuted = "IsMuted"
        case volumeLevel = "VolumeLevel"
    }
}

struct PlaybackStopReport: Codable {
    let itemId: String
    let playSessionId: String
    let mediaSourceId: String
    let positionTicks: Int64
    let failed: Bool

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case playSessionId = "PlaySessionId"
        case mediaSourceId = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case failed = "Failed"
    }
}

struct StreamParams {
    let userId: String
    let mediaSourceId: String
    let playSessionId: String
    let liveStreamId: String?
    let isLiveTv: Bool
    let deviceId: String
    let container: String
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let maxStreamingBitrate: Int64?
    let startTimeTicks: Int64?
}

struct GetItemsRequest {
    let userId: String?
    let parentId: String?
    let recursive: Bool?
    let includeItemTypes: [ItemType]?
    let excludeItemTypes: [ItemType]?
    let sortBy: [ItemSortBy]?
    let sortOrder: SortOrder?
    let filters: [ItemFilter]?
    let fields: [ItemField]?
    let searchTerm: String?
    let limit: Int?
    let startIndex: Int?
    let isFavorite: Bool?
    let mediaTypes: [MediaType]?
    let artistIds: [String]?
    let personIds: [String]?
    let studioIds: [String]?
    let genres: [String]?
    let tags: [String]?
    let years: [Int]?
    let ids: [String]?
    let enableImages: Bool?
    let imageTypeLimit: Int?
    let enableUserData: Bool?
    let groupItems: Bool?
    let nameStartsWith: String?
    let collapseBoxSetItems: Bool?
    let enableTotalRecordCount: Bool?

    init(
        userId: String? = nil,
        parentId: String? = nil,
        recursive: Bool? = nil,
        includeItemTypes: [ItemType]? = nil,
        excludeItemTypes: [ItemType]? = nil,
        sortBy: [ItemSortBy]? = nil,
        sortOrder: SortOrder? = nil,
        filters: [ItemFilter]? = nil,
        fields: [ItemField]? = nil,
        searchTerm: String? = nil,
        limit: Int? = nil,
        startIndex: Int? = nil,
        isFavorite: Bool? = nil,
        mediaTypes: [MediaType]? = nil,
        artistIds: [String]? = nil,
        personIds: [String]? = nil,
        studioIds: [String]? = nil,
        genres: [String]? = nil,
        tags: [String]? = nil,
        years: [Int]? = nil,
        ids: [String]? = nil,
        enableImages: Bool? = nil,
        imageTypeLimit: Int? = nil,
        enableUserData: Bool? = nil,
        groupItems: Bool? = nil,
        nameStartsWith: String? = nil,
        collapseBoxSetItems: Bool? = nil,
        enableTotalRecordCount: Bool? = nil
    ) {
        self.userId = userId
        self.parentId = parentId
        self.recursive = recursive
        self.includeItemTypes = includeItemTypes
        self.excludeItemTypes = excludeItemTypes
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.filters = filters
        self.fields = fields
        self.searchTerm = searchTerm
        self.limit = limit
        self.startIndex = startIndex
        self.isFavorite = isFavorite
        self.mediaTypes = mediaTypes
        self.artistIds = artistIds
        self.personIds = personIds
        self.studioIds = studioIds
        self.genres = genres
        self.tags = tags
        self.years = years
        self.ids = ids
        self.enableImages = enableImages
        self.imageTypeLimit = imageTypeLimit
        self.enableUserData = enableUserData
        self.groupItems = groupItems
        self.nameStartsWith = nameStartsWith
        self.collapseBoxSetItems = collapseBoxSetItems
        self.enableTotalRecordCount = enableTotalRecordCount
    }
}

struct GetResumeItemsRequest {
    let userId: String?
    let parentId: String?
    let includeItemTypes: [ItemType]?
    let excludeItemTypes: [ItemType]?
    let mediaTypes: [MediaType]?
    let fields: [ItemField]?
    let limit: Int?
    let startIndex: Int?
    let enableImages: Bool?
    let imageTypeLimit: Int?

    init(
        userId: String? = nil,
        parentId: String? = nil,
        includeItemTypes: [ItemType]? = nil,
        excludeItemTypes: [ItemType]? = nil,
        mediaTypes: [MediaType]? = nil,
        fields: [ItemField]? = nil,
        limit: Int? = nil,
        startIndex: Int? = nil,
        enableImages: Bool? = nil,
        imageTypeLimit: Int? = nil
    ) {
        self.userId = userId
        self.parentId = parentId
        self.includeItemTypes = includeItemTypes
        self.excludeItemTypes = excludeItemTypes
        self.mediaTypes = mediaTypes
        self.fields = fields
        self.limit = limit
        self.startIndex = startIndex
        self.enableImages = enableImages
        self.imageTypeLimit = imageTypeLimit
    }
}

struct GetLatestMediaRequest {
    let userId: String?
    let parentId: String?
    let includeItemTypes: [ItemType]?
    let fields: [ItemField]?
    let limit: Int?
    let groupItems: Bool?
    let imageTypeLimit: Int?

    init(
        userId: String? = nil,
        parentId: String? = nil,
        includeItemTypes: [ItemType]? = nil,
        fields: [ItemField]? = nil,
        limit: Int? = nil,
        groupItems: Bool? = nil,
        imageTypeLimit: Int? = nil
    ) {
        self.userId = userId
        self.parentId = parentId
        self.includeItemTypes = includeItemTypes
        self.fields = fields
        self.limit = limit
        self.groupItems = groupItems
        self.imageTypeLimit = imageTypeLimit
    }
}

struct GetNextUpRequest {
    let userId: String?
    let seriesId: String?
    let fields: [ItemField]?
    let limit: Int?
    let startIndex: Int?
    let enableImages: Bool?
    let imageTypeLimit: Int?

    init(
        userId: String? = nil,
        seriesId: String? = nil,
        fields: [ItemField]? = nil,
        limit: Int? = nil,
        startIndex: Int? = nil,
        enableImages: Bool? = nil,
        imageTypeLimit: Int? = nil
    ) {
        self.userId = userId
        self.seriesId = seriesId
        self.fields = fields
        self.limit = limit
        self.startIndex = startIndex
        self.enableImages = enableImages
        self.imageTypeLimit = imageTypeLimit
    }
}

struct LiveTvGuideInfo: Codable {
    let startDate: Date?
    let endDate: Date?

    enum CodingKeys: String, CodingKey {
        case startDate = "StartDate"
        case endDate = "EndDate"
    }
}

struct LiveTvTimerInfo: Codable {
    let id: String
    let name: String?
    let channelId: String?
    let channelName: String?
    let programId: String?
    let seriesTimerId: String?
    let startDate: Date?
    let endDate: Date?
    let prePaddingSeconds: Int?
    let postPaddingSeconds: Int?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case channelId = "ChannelId"
        case channelName = "ChannelName"
        case programId = "ProgramId"
        case seriesTimerId = "SeriesTimerId"
        case startDate = "StartDate"
        case endDate = "EndDate"
        case prePaddingSeconds = "PrePaddingSeconds"
        case postPaddingSeconds = "PostPaddingSeconds"
        case status = "Status"
    }
}

struct LiveTvSeriesTimerInfo: Codable {
    let id: String
    let name: String?
    let channelId: String?
    let channelName: String?
    let recordAnyChannel: Bool?
    let recordAnyTime: Bool?
    let recordNewOnly: Bool?
    let startDate: Date?
    let endDate: Date?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case channelId = "ChannelId"
        case channelName = "ChannelName"
        case recordAnyChannel = "RecordAnyChannel"
        case recordAnyTime = "RecordAnyTime"
        case recordNewOnly = "RecordNewOnly"
        case startDate = "StartDate"
        case endDate = "EndDate"
    }
}
