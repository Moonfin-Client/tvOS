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
    case tomatoesAudience = "tomatoes_audience"
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

    static let communityRawValue = "stars"
    static let tmdbEpisodeRawValue = "tmdb_episode"
    private static let baseSourcesWhenAdditionalDisabled: Set<String> = [
        communityRawValue,
        "tomatoes",
        tmdbEpisodeRawValue,
    ]

    static var defaultEnabledSourceOrder: [String] {
        SettingsRatingSource.defaultOrder.map(\.rawValue)
    }

    static var knownSettingsSourceRawValues: Set<String> {
        Set(SettingsRatingSource.allCases.map(\.rawValue))
    }

    static func canonicalSourceRawValue(_ rawSource: String) -> String {
        let source = rawSource
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch source {
        case "rt":
            return "tomatoes"
        case "rt_audience", "rtaudience", "tomatoes_audience", "tomatoesaudience", "popcorn":
            return "tomatoes_audience"
        case "metacritic_user", "metacritic user":
            return "metacriticuser"
        case "roger_ebert", "roger ebert":
            return "rogerebert"
        case "community", "community_rating", "communityrating", "stars":
            return communityRawValue
        case "tmdbepisode":
            return tmdbEpisodeRawValue
        default:
            return source
        }
    }

    static func canonicalEnabledSourceOrder(_ rawSources: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for rawSource in rawSources {
            let canonical = canonicalSourceRawValue(rawSource)
            guard !canonical.isEmpty else { continue }
            if seen.insert(canonical).inserted {
                result.append(canonical)
            }
        }

        return result
    }

    static func normalizedApiRating(source: String, rawValue: Float) -> (source: String, normalizedValue: Float)? {
        guard rawValue > 0 else { return nil }
        let canonical = canonicalSourceRawValue(source)

        if canonical == communityRawValue {
            return (source: canonical, normalizedValue: rawValue)
        }

        if let sourceModel = RatingSource(rawValue: canonical) {
            return (source: canonical, normalizedValue: sourceModel.normalize(rawValue))
        }

        return (source: canonical, normalizedValue: rawValue / 100.0)
    }

    static func isSourceEnabled(_ sourceRawValue: String, enabledSourcesOrdered: [String]) -> Bool {
        let canonicalSource = canonicalSourceRawValue(sourceRawValue)
        let canonicalEnabled = Set(canonicalEnabledSourceOrder(enabledSourcesOrdered))

        if canonicalSource == tmdbEpisodeRawValue {
            return canonicalEnabled.contains("tmdb")
        }

        if canonicalEnabled.contains(canonicalSource) {
            return true
        }

        if knownSettingsSourceRawValues.contains(canonicalSource) {
            return false
        }

        return true
    }

    static func allowsAdditionalRatings(_ sourceRawValue: String, enableAdditionalRatings: Bool) -> Bool {
        if enableAdditionalRatings {
            return true
        }
        return baseSourcesWhenAdditionalDisabled.contains(canonicalSourceRawValue(sourceRawValue))
    }

    static func orderKey(_ sourceRawValue: String) -> String {
        let canonical = canonicalSourceRawValue(sourceRawValue)
        if canonical == tmdbEpisodeRawValue {
            return "tmdb"
        }
        return canonical
    }

    private static func l(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    var label: String {
        switch self {
        case .tomatoes: return Self.l("rating_rotten_tomatoes")
        case .tomatoesAudience, .popcorn: return Self.l("rating_rt_audience")
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
        case .tomatoes, .tomatoesAudience, .popcorn, .tmdb, .tmdbEpisode, .metacritic, .metacriticuser, .trakt, .anilist: return value / 100.0
        case .imdb, .myanimelist: return value / 10.0
        case .letterboxd: return value / 5.0
        case .rogerebert: return value / 4.0
        }
    }

    func format(_ normalized: Float) -> String {
        switch self {
        case .tomatoes, .tomatoesAudience, .popcorn, .tmdb, .tmdbEpisode, .metacritic, .metacriticuser, .trakt, .anilist:
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

struct RatingDisplayPolicy {
    static func apply(
        ratings: [(String, Float)],
        enabledSourcesOrdered: [String],
        enableAdditionalRatings: Bool,
        isEpisode: Bool = false,
        enableEpisodeRatings: Bool = false,
        hasEpisodeRating: Bool = false
    ) -> [(String, Float)] {
        let canonicalEnabledOrder = RatingSource.canonicalEnabledSourceOrder(enabledSourcesOrdered)
        let orderIndexBySource = Dictionary(uniqueKeysWithValues: canonicalEnabledOrder.enumerated().map { ($1, $0) })

        var seenSources = Set<String>()
        let canonicalized = ratings.enumerated().compactMap { index, rating -> (source: String, value: Float, originalIndex: Int)? in
            let canonicalSource = RatingSource.canonicalSourceRawValue(rating.0)
            guard !canonicalSource.isEmpty else { return nil }
            guard rating.1 > 0 else { return nil }
            guard seenSources.insert(canonicalSource).inserted else { return nil }
            return (source: canonicalSource, value: rating.1, originalIndex: index)
        }

        let filtered = canonicalized.filter { rating in
            if !RatingSource.allowsAdditionalRatings(rating.source, enableAdditionalRatings: enableAdditionalRatings) {
                return false
            }

            if rating.source == RatingSource.tmdbEpisodeRawValue {
                return isEpisode && enableEpisodeRatings && RatingSource.isSourceEnabled(rating.source, enabledSourcesOrdered: canonicalEnabledOrder)
            }

            if rating.source == "tmdb" && isEpisode && enableEpisodeRatings && hasEpisodeRating {
                return false
            }

            return RatingSource.isSourceEnabled(rating.source, enabledSourcesOrdered: canonicalEnabledOrder)
        }

        return filtered
            .sorted { lhs, rhs in
                let lhsIndex = orderIndexBySource[RatingSource.orderKey(lhs.source)] ?? Int.max
                let rhsIndex = orderIndexBySource[RatingSource.orderKey(rhs.source)] ?? Int.max

                if lhsIndex != rhsIndex {
                    return lhsIndex < rhsIndex
                }

                return lhs.originalIndex < rhs.originalIndex
            }
            .map { ($0.source, $0.value) }
    }
}
