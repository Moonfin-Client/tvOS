import Foundation

struct RatingIconProvider {
    static func getIcon(source: String, scorePercent: Int? = nil) -> String? {
        return localAssetName(source: RatingSource.canonicalSourceRawValue(source), scorePercent: scorePercent)
    }

    private static func localAssetName(source: String, scorePercent: Int?) -> String? {
        switch source {
        case "tomatoes":
            if let s = scorePercent {
                if s >= 75 { return "rating-rt-certified" }
                if s < 60 { return "rating-rt-rotten" }
            }
            return "rating-rt-fresh"

        case "tomatoes_audience", "popcorn":
            if let s = scorePercent {
                if s >= 90 { return "rating-rt-verified" }
                if s < 60 { return "rating-rt-audience-down" }
            }
            return "rating-rt-audience-up"

        case "metacritic":
            if let s = scorePercent, s >= 81 { return "rating-metacritic-score" }
            return "rating-metacritic"

        case "metacriticuser": return "rating-metacritic-user"
        case "imdb": return "rating-imdb"
        case "tmdb", "tmdb_episode": return "rating-tmdb"
        case "trakt": return "rating-trakt"
        case "letterboxd": return "rating-letterboxd"
        case "rogerebert": return "rating-rogerebert"
        case "myanimelist": return "rating-mal"
        case "anilist": return "rating-anilist"
        default: return nil
        }
    }
}
