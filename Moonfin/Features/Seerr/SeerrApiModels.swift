import Foundation

// MARK: - Request Models

struct SeerrRequestDto: Codable, Identifiable {
    let id: Int
    let status: Int
    let createdAt: String?
    let updatedAt: String?
    let type: String
    let media: SeerrMediaDto?
    let requestedBy: SeerrUserDto?
    let seasonCount: Int?
    let externalId: String?
    let is4k: Bool
    let seasons: [SeerrSeasonRequestDto]?

    static let statusPending = 1
    static let statusApproved = 2
    static let statusDeclined = 3
    static let statusAvailable = 4

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        status = try c.decode(Int.self, forKey: .status)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        type = try c.decode(String.self, forKey: .type)
        media = try c.decodeIfPresent(SeerrMediaDto.self, forKey: .media)
        requestedBy = try c.decodeIfPresent(SeerrUserDto.self, forKey: .requestedBy)
        seasonCount = try c.decodeIfPresent(Int.self, forKey: .seasonCount)
        externalId = try c.decodeIfPresent(String.self, forKey: .externalId)
        is4k = try c.decodeIfPresent(Bool.self, forKey: .is4k) ?? false
        seasons = try c.decodeIfPresent([SeerrSeasonRequestDto].self, forKey: .seasons)
    }
}

struct SeerrSeasonRequestDto: Codable, Identifiable {
    let id: Int
    let seasonNumber: Int
    let status: Int
    let createdAt: String?
    let updatedAt: String?
}

struct SeerrMediaDto: Codable, Identifiable {
    let id: Int
    let mediaType: String?
    let tmdbId: Int?
    let tvdbId: Int?
    let imdbId: String?
    let status: Int?
    let status4k: Int?
    let mediaAddedAt: String?
    let serviceId: Int?
    let serviceId4k: Int?
    let externalServiceId: Int?
    let externalServiceId4k: Int?
    let externalServiceSlug: String?
    let externalServiceSlug4k: String?
    let ratingKey: String?
    let ratingKey4k: String?
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let originalLanguage: String?
    let genreIds: [Int]?
    let voteAverage: Double?
    let externalIds: SeerrExternalIds?
    let requests: [SeerrRequestDto]?
}

struct SeerrExternalIds: Codable {
    let tvdbId: Int?
    let tmdbId: Int?
    let imdbId: String?
}

struct SeerrUserDto: Codable, Identifiable {
    let id: Int
    let username: String?
    let email: String?
    let avatar: String?
    let apiKey: String?
    let permissions: Int?

    static let permissionNone = 0
    static let permissionAdmin = 2
    static let permissionManageSettings = 4
    static let permissionManageUsers = 8
    static let permissionManageRequests = 16
    static let permissionRequest = 32
    static let permissionAutoApprove = 128
    static let permissionRequest4k = 1024
    static let permissionRequest4kMovie = 2048
    static let permissionRequest4kTv = 4096
    static let permissionRequestAdvanced = 8192
    static let permissionRequestMovie = 262144
    static let permissionRequestTv = 524288

    func hasPermission(_ permission: Int) -> Bool {
        let perms = permissions ?? 0
        if perms & Self.permissionAdmin != 0 { return true }
        return perms & permission != 0
    }

    func canRequest4k() -> Bool {
        hasPermission(Self.permissionRequest4k) ||
        hasPermission(Self.permissionRequest4kMovie) ||
        hasPermission(Self.permissionRequest4kTv)
    }

    func canRequest4kMovies() -> Bool {
        hasPermission(Self.permissionRequest4k) || hasPermission(Self.permissionRequest4kMovie)
    }

    func canRequest4kTv() -> Bool {
        hasPermission(Self.permissionRequest4k) || hasPermission(Self.permissionRequest4kTv)
    }

    func hasAdvancedRequestPermission() -> Bool {
        hasPermission(Self.permissionRequestAdvanced) || hasPermission(Self.permissionManageRequests)
    }

    var isAdmin: Bool { hasPermission(Self.permissionAdmin) }
}

// MARK: - Discover/Trending Models

struct SeerrDiscoverPageDto: Codable {
    let results: [SeerrDiscoverItemDto]
    let totalPages: Int
    let totalResults: Int
    let page: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decodeIfPresent([SeerrDiscoverItemDto].self, forKey: .results) ?? []
        totalPages = try c.decodeIfPresent(Int.self, forKey: .totalPages) ?? 0
        totalResults = try c.decodeIfPresent(Int.self, forKey: .totalResults) ?? 0
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
    }
}

struct SeerrDiscoverItemDto: Codable, Identifiable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let originalLanguage: String?
    let genreIds: [Int]
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let adult: Bool
    let mediaInfo: SeerrMediaInfoDto?
    let requestStatus: Int?

    var displayTitle: String { title ?? name ?? "Unknown" }

    var isAvailable: Bool { mediaInfo?.status == 5 || mediaInfo?.status == 4 }
    var isBlacklisted: Bool { mediaInfo?.status == 6 }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        originalTitle = try c.decodeIfPresent(String.self, forKey: .originalTitle)
        originalName = try c.decodeIfPresent(String.self, forKey: .originalName)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        firstAirDate = try c.decodeIfPresent(String.self, forKey: .firstAirDate)
        originalLanguage = try c.decodeIfPresent(String.self, forKey: .originalLanguage)
        genreIds = try c.decodeIfPresent([Int].self, forKey: .genreIds) ?? []
        voteAverage = try c.decodeIfPresent(Double.self, forKey: .voteAverage)
        voteCount = try c.decodeIfPresent(Int.self, forKey: .voteCount)
        popularity = try c.decodeIfPresent(Double.self, forKey: .popularity)
        adult = try c.decodeIfPresent(Bool.self, forKey: .adult) ?? false
        mediaInfo = try c.decodeIfPresent(SeerrMediaInfoDto.self, forKey: .mediaInfo)
        requestStatus = try c.decodeIfPresent(Int.self, forKey: .requestStatus)
    }

    init(id: Int, mediaType: String?, title: String?, name: String?, posterPath: String?,
         backdropPath: String?, overview: String?, releaseDate: String?, firstAirDate: String?,
         genreIds: [Int] = [], voteAverage: Double? = nil, adult: Bool = false,
         mediaInfo: SeerrMediaInfoDto? = nil, requestStatus: Int? = nil) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.name = name
        self.originalTitle = nil
        self.originalName = nil
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.overview = overview
        self.releaseDate = releaseDate
        self.firstAirDate = firstAirDate
        self.originalLanguage = nil
        self.genreIds = genreIds
        self.voteAverage = voteAverage
        self.voteCount = nil
        self.popularity = nil
        self.adult = adult
        self.mediaInfo = mediaInfo
        self.requestStatus = requestStatus
    }

    static func fromRequest(tmdbId: Int, mediaType: String, request: SeerrRequestDto) -> SeerrDiscoverItemDto {
        SeerrDiscoverItemDto(
            id: tmdbId,
            mediaType: mediaType,
            title: mediaType == "movie" ? (request.media?.title ?? request.media?.name) : nil,
            name: mediaType == "tv" ? (request.media?.name ?? request.media?.title) : nil,
            posterPath: request.media?.posterPath,
            backdropPath: request.media?.backdropPath,
            overview: request.media?.overview,
            releaseDate: request.media?.releaseDate,
            firstAirDate: request.media?.firstAirDate,
            requestStatus: request.status
        )
    }

    static func fromMedia(_ media: SeerrMediaDto) -> SeerrDiscoverItemDto? {
        guard let tmdbId = media.tmdbId else { return nil }
        return SeerrDiscoverItemDto(
            id: tmdbId,
            mediaType: media.mediaType,
            title: media.title,
            name: media.name,
            posterPath: media.posterPath,
            backdropPath: media.backdropPath,
            overview: media.overview,
            releaseDate: media.releaseDate,
            firstAirDate: media.firstAirDate,
            mediaInfo: SeerrMediaInfoDto(id: media.id, tmdbId: media.tmdbId, tvdbId: media.tvdbId, status: media.status, status4k: media.status4k, requests: media.requests)
        )
    }
}

struct SeerrMovieDetailsDto: Codable, Identifiable {
    let id: Int
    let mediaType: String?
    let title: String
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let releaseDate: String?
    let status: String?
    let runtime: Int?
    let budget: Int64?
    let revenue: Int64?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [SeerrGenreDto]
    let credits: SeerrCreditsDto?
    let externalIds: SeerrExternalIds?
    let mediaInfo: SeerrMediaInfoDto?
    let keywords: [SeerrKeywordDto]
    let relatedVideos: [SeerrRelatedVideoDto]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        title = try c.decode(String.self, forKey: .title)
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        runtime = try c.decodeIfPresent(Int.self, forKey: .runtime)
        budget = try c.decodeIfPresent(Int64.self, forKey: .budget)
        revenue = try c.decodeIfPresent(Int64.self, forKey: .revenue)
        voteAverage = try c.decodeIfPresent(Double.self, forKey: .voteAverage)
        voteCount = try c.decodeIfPresent(Int.self, forKey: .voteCount)
        genres = try c.decodeIfPresent([SeerrGenreDto].self, forKey: .genres) ?? []
        credits = try c.decodeIfPresent(SeerrCreditsDto.self, forKey: .credits)
        externalIds = try c.decodeIfPresent(SeerrExternalIds.self, forKey: .externalIds)
        mediaInfo = try c.decodeIfPresent(SeerrMediaInfoDto.self, forKey: .mediaInfo)
        keywords = try c.decodeIfPresent([SeerrKeywordDto].self, forKey: .keywords) ?? []
        let videos = try? c.decodeIfPresent(SeerrRelatedVideosDto.self, forKey: .relatedVideos)
        relatedVideos = videos?.results ?? []
    }
}

struct SeerrTvDetailsDto: Codable, Identifiable {
    let id: Int
    let mediaType: String?
    let name: String?
    let title: String?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let tagline: String?
    let firstAirDate: String?
    let lastAirDate: String?
    let status: String?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [SeerrGenreDto]
    let credits: SeerrCreditsDto?
    let networks: [SeerrNetworkDto]
    let externalIds: SeerrExternalIds?
    let mediaInfo: SeerrMediaInfoDto?
    let keywords: [SeerrKeywordDto]
    let relatedVideos: [SeerrRelatedVideoDto]

    var displayTitle: String { name ?? title ?? "Unknown" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline)
        firstAirDate = try c.decodeIfPresent(String.self, forKey: .firstAirDate)
        lastAirDate = try c.decodeIfPresent(String.self, forKey: .lastAirDate)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        numberOfSeasons = try c.decodeIfPresent(Int.self, forKey: .numberOfSeasons)
        numberOfEpisodes = try c.decodeIfPresent(Int.self, forKey: .numberOfEpisodes)
        voteAverage = try c.decodeIfPresent(Double.self, forKey: .voteAverage)
        voteCount = try c.decodeIfPresent(Int.self, forKey: .voteCount)
        genres = try c.decodeIfPresent([SeerrGenreDto].self, forKey: .genres) ?? []
        credits = try c.decodeIfPresent(SeerrCreditsDto.self, forKey: .credits)
        networks = try c.decodeIfPresent([SeerrNetworkDto].self, forKey: .networks) ?? []
        externalIds = try c.decodeIfPresent(SeerrExternalIds.self, forKey: .externalIds)
        mediaInfo = try c.decodeIfPresent(SeerrMediaInfoDto.self, forKey: .mediaInfo)
        keywords = try c.decodeIfPresent([SeerrKeywordDto].self, forKey: .keywords) ?? []
        let videos = try? c.decodeIfPresent(SeerrRelatedVideosDto.self, forKey: .relatedVideos)
        relatedVideos = videos?.results ?? []
    }
}

// MARK: - Supporting Models

struct SeerrGenreDto: Codable, Identifiable {
    let id: Int
    let name: String
    let backdrops: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        backdrops = try c.decodeIfPresent([String].self, forKey: .backdrops) ?? []
    }
}

struct SeerrNetworkDto: Codable, Identifiable {
    let id: Int
    let name: String
    let logoPath: String?
    let originCountry: String?
}

struct SeerrStudioDto: Codable, Identifiable {
    let id: Int
    let name: String
    let logoPath: String?
}

struct SeerrKeywordDto: Codable, Identifiable {
    let id: Int
    let name: String
}

struct SeerrCreditsDto: Codable {
    let cast: [SeerrCastMemberDto]
    let crew: [SeerrCrewMemberDto]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cast = try c.decodeIfPresent([SeerrCastMemberDto].self, forKey: .cast) ?? []
        crew = try c.decodeIfPresent([SeerrCrewMemberDto].self, forKey: .crew) ?? []
    }
}

struct SeerrCastMemberDto: Codable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    let order: Int?
}

struct SeerrCrewMemberDto: Codable, Identifiable {
    let id: Int
    let name: String
    let department: String?
    let job: String?
    let profilePath: String?
}

struct SeerrRelatedVideoDto: Codable {
    let key: String?
    let type: String?
    let site: String?
}

struct SeerrRelatedVideosDto: Codable {
    let results: [SeerrRelatedVideoDto]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = (try? c.decodeIfPresent([SeerrRelatedVideoDto].self, forKey: .results)) ?? []
    }
}

struct SeerrMediaInfoDto: Codable {
    let id: Int?
    let tmdbId: Int?
    let tvdbId: Int?
    let status: Int?
    let status4k: Int?
    let requests: [SeerrRequestDto]?

    static let statusUnknown = 1
    static let statusPending = 2
    static let statusProcessing = 3
    static let statusPartiallyAvailable = 4
    static let statusAvailable = 5
    static let statusBlacklisted = 6
}

// MARK: - Person Models

struct SeerrPersonDetailsDto: Codable, Identifiable {
    let id: Int
    let name: String
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let profilePath: String?
    let knownForDepartment: String?
    let popularity: Double?
}

struct SeerrPersonCombinedCreditsDto: Codable {
    let cast: [SeerrDiscoverItemDto]
    let crew: [SeerrDiscoverItemDto]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cast = try c.decodeIfPresent([SeerrDiscoverItemDto].self, forKey: .cast) ?? []
        crew = try c.decodeIfPresent([SeerrDiscoverItemDto].self, forKey: .crew) ?? []
    }
}

// MARK: - Request/Response Wrappers

struct SeerrListResponse<T: Codable>: Codable {
    let pageInfo: SeerrPageInfoDto?
    let results: [T]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pageInfo = try c.decodeIfPresent(SeerrPageInfoDto.self, forKey: .pageInfo)
        results = try c.decodeIfPresent([T].self, forKey: .results) ?? []
    }
}

struct SeerrPageInfoDto: Codable {
    let pages: Int
    let pageSize: Int
    let results: Int
    let page: Int
}

struct SeerrCreateRequestBody: Codable {
    let mediaId: Int
    let mediaType: String
    let seasons: SeerrSeasons?
    let is4k: Bool
    let profileId: Int?
    let rootFolderId: Int?
    let serverId: Int?
}

enum SeerrSeasons: Codable {
    case list([Int])
    case all

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .list(let ids): try container.encode(ids)
        case .all: try container.encode("all")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let ids = try? container.decode([Int].self) {
            self = .list(ids)
        } else if let str = try? container.decode(String.self), str == "all" {
            self = .all
        } else {
            self = .all
        }
    }
}

// MARK: - Settings/Configuration

struct SeerrMainSettingsDto: Codable {
    let apiKey: String
    let appLanguage: String?
    let applicationTitle: String?
    let applicationUrl: String?
    let hideAvailable: Bool?
    let partialRequestsEnabled: Bool?
    let localLogin: Bool?
    let mediaServerType: Int?
    let newPlexLogin: Bool?
    let defaultPermissions: Int?
    let enableSpecialEpisodes: Bool?
}

struct SeerrStatusDto: Codable {
    let appData: SeerrAppDataDto?
}

struct SeerrAppDataDto: Codable {
    let version: String?
    let initialized: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        initialized = try c.decodeIfPresent(Bool.self, forKey: .initialized) ?? false
    }
}

// MARK: - Service Configuration

struct SeerrRadarrSettingsDto: Codable, Identifiable {
    let id: Int
    let name: String
    let hostname: String
    let port: Int
    let apiKey: String
    let useSsl: Bool
    let baseUrl: String?
    let activeProfileId: Int
    let activeProfileName: String
    let activeDirectory: String
    let activeAnimeProfileId: Int?
    let activeAnimeProfileName: String?
    let activeAnimeDirectory: String?
    let is4k: Bool
    let minimumAvailability: String
    let isDefault: Bool
    let externalUrl: String?
    let syncEnabled: Bool
    let preventSearch: Bool
    let tagRequests: Bool
    let tags: [Int]
    let profiles: [SeerrQualityProfileDto]
    let rootFolders: [SeerrRootFolderDto]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        hostname = try c.decode(String.self, forKey: .hostname)
        port = try c.decode(Int.self, forKey: .port)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        useSsl = try c.decodeIfPresent(Bool.self, forKey: .useSsl) ?? false
        baseUrl = try c.decodeIfPresent(String.self, forKey: .baseUrl)
        activeProfileId = try c.decode(Int.self, forKey: .activeProfileId)
        activeProfileName = try c.decode(String.self, forKey: .activeProfileName)
        activeDirectory = try c.decode(String.self, forKey: .activeDirectory)
        activeAnimeProfileId = try c.decodeIfPresent(Int.self, forKey: .activeAnimeProfileId)
        activeAnimeProfileName = try c.decodeIfPresent(String.self, forKey: .activeAnimeProfileName)
        activeAnimeDirectory = try c.decodeIfPresent(String.self, forKey: .activeAnimeDirectory)
        is4k = try c.decodeIfPresent(Bool.self, forKey: .is4k) ?? false
        minimumAvailability = try c.decode(String.self, forKey: .minimumAvailability)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        externalUrl = try c.decodeIfPresent(String.self, forKey: .externalUrl)
        syncEnabled = try c.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? false
        preventSearch = try c.decodeIfPresent(Bool.self, forKey: .preventSearch) ?? false
        tagRequests = try c.decodeIfPresent(Bool.self, forKey: .tagRequests) ?? false
        tags = try c.decodeIfPresent([Int].self, forKey: .tags) ?? []
        profiles = try c.decodeIfPresent([SeerrQualityProfileDto].self, forKey: .profiles) ?? []
        rootFolders = try c.decodeIfPresent([SeerrRootFolderDto].self, forKey: .rootFolders) ?? []
    }
}

struct SeerrSonarrSettingsDto: Codable, Identifiable {
    let id: Int
    let name: String
    let hostname: String
    let port: Int
    let apiKey: String
    let useSsl: Bool
    let baseUrl: String?
    let activeProfileId: Int
    let activeProfileName: String
    let activeDirectory: String
    let activeAnimeProfileId: Int?
    let activeAnimeProfileName: String?
    let activeAnimeDirectory: String?
    let activeLanguageProfileId: Int?
    let is4k: Bool
    let enableSeasonFolders: Bool
    let isDefault: Bool
    let externalUrl: String?
    let syncEnabled: Bool
    let preventSearch: Bool
    let tagRequests: Bool
    let tags: [Int]
    let profiles: [SeerrQualityProfileDto]
    let rootFolders: [SeerrRootFolderDto]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        hostname = try c.decode(String.self, forKey: .hostname)
        port = try c.decode(Int.self, forKey: .port)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        useSsl = try c.decodeIfPresent(Bool.self, forKey: .useSsl) ?? false
        baseUrl = try c.decodeIfPresent(String.self, forKey: .baseUrl)
        activeProfileId = try c.decode(Int.self, forKey: .activeProfileId)
        activeProfileName = try c.decode(String.self, forKey: .activeProfileName)
        activeDirectory = try c.decode(String.self, forKey: .activeDirectory)
        activeAnimeProfileId = try c.decodeIfPresent(Int.self, forKey: .activeAnimeProfileId)
        activeAnimeProfileName = try c.decodeIfPresent(String.self, forKey: .activeAnimeProfileName)
        activeAnimeDirectory = try c.decodeIfPresent(String.self, forKey: .activeAnimeDirectory)
        activeLanguageProfileId = try c.decodeIfPresent(Int.self, forKey: .activeLanguageProfileId)
        is4k = try c.decodeIfPresent(Bool.self, forKey: .is4k) ?? false
        enableSeasonFolders = try c.decodeIfPresent(Bool.self, forKey: .enableSeasonFolders) ?? false
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        externalUrl = try c.decodeIfPresent(String.self, forKey: .externalUrl)
        syncEnabled = try c.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? false
        preventSearch = try c.decodeIfPresent(Bool.self, forKey: .preventSearch) ?? false
        tagRequests = try c.decodeIfPresent(Bool.self, forKey: .tagRequests) ?? false
        tags = try c.decodeIfPresent([Int].self, forKey: .tags) ?? []
        profiles = try c.decodeIfPresent([SeerrQualityProfileDto].self, forKey: .profiles) ?? []
        rootFolders = try c.decodeIfPresent([SeerrRootFolderDto].self, forKey: .rootFolders) ?? []
    }
}

struct SeerrQualityProfileDto: Codable, Identifiable {
    let id: Int
    let name: String
}

struct SeerrRootFolderDto: Codable, Identifiable {
    let id: Int
    let path: String
    let freeSpace: Int64?
    let totalSpace: Int64?
}

struct SeerrTagDto: Codable, Identifiable {
    let id: Int
    let label: String
}

// MARK: - Service API Models (non-admin)

struct SeerrServiceServerDto: Codable, Identifiable {
    let id: Int
    let name: String
    let is4k: Bool
    let isDefault: Bool
    let activeProfileId: Int
    let activeDirectory: String
    let activeAnimeProfileId: Int?
    let activeAnimeDirectory: String?
    let activeLanguageProfileId: Int?
    let activeAnimeLanguageProfileId: Int?
    let activeTags: [Int]
    let activeAnimeTags: [Int]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        is4k = try c.decodeIfPresent(Bool.self, forKey: .is4k) ?? false
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        activeProfileId = try c.decode(Int.self, forKey: .activeProfileId)
        activeDirectory = try c.decode(String.self, forKey: .activeDirectory)
        activeAnimeProfileId = try c.decodeIfPresent(Int.self, forKey: .activeAnimeProfileId)
        activeAnimeDirectory = try c.decodeIfPresent(String.self, forKey: .activeAnimeDirectory)
        activeLanguageProfileId = try c.decodeIfPresent(Int.self, forKey: .activeLanguageProfileId)
        activeAnimeLanguageProfileId = try c.decodeIfPresent(Int.self, forKey: .activeAnimeLanguageProfileId)
        activeTags = try c.decodeIfPresent([Int].self, forKey: .activeTags) ?? []
        activeAnimeTags = try c.decodeIfPresent([Int].self, forKey: .activeAnimeTags)
    }
}

struct SeerrServiceServerDetailsDto: Codable {
    let server: SeerrServiceServerDto
    let profiles: [SeerrQualityProfileDto]
    let rootFolders: [SeerrRootFolderDto]
    let languageProfiles: [SeerrLanguageProfileDto]?
    let tags: [SeerrTagDto]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server = try c.decode(SeerrServiceServerDto.self, forKey: .server)
        profiles = try c.decodeIfPresent([SeerrQualityProfileDto].self, forKey: .profiles) ?? []
        rootFolders = try c.decodeIfPresent([SeerrRootFolderDto].self, forKey: .rootFolders) ?? []
        languageProfiles = try c.decodeIfPresent([SeerrLanguageProfileDto].self, forKey: .languageProfiles)
        tags = try c.decodeIfPresent([SeerrTagDto].self, forKey: .tags) ?? []
    }
}

struct SeerrLanguageProfileDto: Codable, Identifiable {
    let id: Int
    let name: String
}

// MARK: - Moonfin Proxy Models

struct MoonfinProxyConfig {
    let jellyfinBaseUrl: String
    let jellyfinToken: String
}

struct MoonfinStatusResponse: Codable {
    let enabled: Bool
    let authenticated: Bool
    let url: String?
    let jellyseerrUserId: Int?
    let displayName: String?
    let avatar: String?
    let permissions: Int
    let sessionCreated: Int64?
    let lastValidated: Int64?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        authenticated = try c.decodeIfPresent(Bool.self, forKey: .authenticated) ?? false
        url = try c.decodeIfPresent(String.self, forKey: .url)
        jellyseerrUserId = try c.decodeIfPresent(Int.self, forKey: .jellyseerrUserId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        permissions = try c.decodeIfPresent(Int.self, forKey: .permissions) ?? 0
        sessionCreated = try c.decodeIfPresent(Int64.self, forKey: .sessionCreated)
        lastValidated = try c.decodeIfPresent(Int64.self, forKey: .lastValidated)
    }
}

struct MoonfinLoginRequest: Codable {
    let username: String
    let password: String
    let authType: String
}

struct MoonfinLoginResponse: Codable {
    let success: Bool
    let error: String?
    let jellyseerrUserId: Int?
    let displayName: String?
    let avatar: String?
    let permissions: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
        jellyseerrUserId = try c.decodeIfPresent(Int.self, forKey: .jellyseerrUserId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        permissions = try c.decodeIfPresent(Int.self, forKey: .permissions) ?? 0
    }
}

struct MoonfinValidateResponse: Codable {
    let valid: Bool
    let lastValidated: Int64?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        valid = try c.decodeIfPresent(Bool.self, forKey: .valid) ?? false
        lastValidated = try c.decodeIfPresent(Int64.self, forKey: .lastValidated)
    }
}
