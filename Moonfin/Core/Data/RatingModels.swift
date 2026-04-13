import Foundation

struct MdbListRating: Codable {
    let source: String?
    let value: Float?
    let score: Float?
    let votes: Int?
    let url: String?
}

struct MdbListResponse: Codable {
    let success: Bool
    let error: String?
    let ratings: [MdbListRating]?

    private enum CodingKeys: String, CodingKey {
        case success, error, ratings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = (try? container.decode(Bool.self, forKey: .success)) ?? false
        self.error = try? container.decode(String.self, forKey: .error)
        self.ratings = try? container.decode([MdbListRating].self, forKey: .ratings)
    }
}

struct TmdbEpisodeResponse: Codable {
    let success: Bool
    let error: String?
    let voteAverage: Float?
    let voteCount: Int?
    let name: String?
    let airDate: String?
    let seasonNumber: Int?
    let episodeNumber: Int?

    private enum CodingKeys: String, CodingKey {
        case success, error, voteAverage, voteCount, name, airDate, seasonNumber, episodeNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = (try? container.decode(Bool.self, forKey: .success)) ?? false
        self.error = try? container.decode(String.self, forKey: .error)
        self.voteAverage = try? container.decode(Float.self, forKey: .voteAverage)
        self.voteCount = try? container.decode(Int.self, forKey: .voteCount)
        self.name = try? container.decode(String.self, forKey: .name)
        self.airDate = try? container.decode(String.self, forKey: .airDate)
        self.seasonNumber = try? container.decode(Int.self, forKey: .seasonNumber)
        self.episodeNumber = try? container.decode(Int.self, forKey: .episodeNumber)
    }
}

struct TmdbSeasonEpisode: Codable {
    let voteAverage: Float?
    let voteCount: Int?
    let episodeNumber: Int?
}

struct TmdbSeasonResponse: Codable {
    let success: Bool
    let error: String?
    let seasonName: String?
    let episodes: [TmdbSeasonEpisode]?

    private enum CodingKeys: String, CodingKey {
        case success, error, seasonName, episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = (try? container.decode(Bool.self, forKey: .success)) ?? false
        self.error = try? container.decode(String.self, forKey: .error)
        self.seasonName = try? container.decode(String.self, forKey: .seasonName)
        self.episodes = try? container.decode([TmdbSeasonEpisode].self, forKey: .episodes)
    }
}

enum RatingSource: String, CaseIterable {
    case tomatoes
    case popcorn
    case imdb
    case tmdb
    case tmdbEpisode = "tmdb_episode"
    case metacritic
    case metacriticuser
    case trakt
    case letterboxd
    case rogerebert
    case myanimelist
    case anilist

    private static func l(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    var label: String {
        switch self {
        case .tomatoes: return Self.l("rating_rotten_tomatoes")
        case .popcorn: return Self.l("rating_rt_audience")
        case .imdb: return Self.l("rating_imdb")
        case .tmdb, .tmdbEpisode: return Self.l("rating_tmdb")
        case .metacritic: return Self.l("rating_metacritic")
        case .metacriticuser: return Self.l("rating_metacritic_user")
        case .trakt: return Self.l("rating_trakt")
        case .letterboxd: return Self.l("rating_letterboxd")
        case .rogerebert: return Self.l("rating_roger_ebert")
        case .myanimelist: return Self.l("rating_myanimelist")
        case .anilist: return Self.l("rating_anilist")
        }
    }

    func normalize(_ value: Float) -> Float {
        switch self {
        case .tomatoes, .popcorn, .tmdb, .tmdbEpisode, .metacritic, .metacriticuser, .trakt, .anilist: return value / 100.0
        case .imdb, .myanimelist: return value / 10.0
        case .letterboxd: return value / 5.0
        case .rogerebert: return value / 4.0
        }
    }

    func format(_ normalized: Float) -> String {
        switch self {
        case .tomatoes, .popcorn, .tmdb, .tmdbEpisode, .metacritic, .metacriticuser, .trakt, .anilist:
            return "\(Int(normalized * 100))%"
        case .letterboxd:
            return String(format: "%.1f", normalized * 5.0)
        case .rogerebert:
            return String(format: "%.1f", normalized * 4.0)
        case .imdb, .myanimelist:
            return String(format: "%.1f", normalized * 10.0)
        }
    }
}
