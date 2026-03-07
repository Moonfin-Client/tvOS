import SwiftUI

struct RatingChipView: View {
    let source: String
    let normalizedValue: Float
    let showLabel: Bool

    var body: some View {
        let scorePercent = Int(normalizedValue * 100)
        if let iconName = RatingIconProvider.getIcon(source: source, scorePercent: scorePercent) {
            let ratingSource = RatingSource(rawValue: source)
            let formatted = ratingSource?.format(normalizedValue) ?? "\(scorePercent)%"
            let label = ratingSource?.label ?? source

            HStack(spacing: 6) {
                Image(iconName).resizable().aspectRatio(contentMode: .fit).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(formatted)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    if showLabel {
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
        }
    }
}

struct CompactRatingChipView: View {
    let source: String
    let normalizedValue: Float

    var body: some View {
        let scorePercent = Int(normalizedValue * 100)
        if let iconName = RatingIconProvider.getIcon(source: source, scorePercent: scorePercent) {
            let ratingSource = RatingSource(rawValue: source)
            let formatted = ratingSource?.format(normalizedValue) ?? "\(scorePercent)%"

            HStack(spacing: 3) {
                Image(iconName).resizable().aspectRatio(contentMode: .fit).frame(width: 14, height: 14)
                Text(formatted)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

struct MediaBarRatingRow: View {
    let source: String
    let value: Float

    var body: some View {
        if source == "stars" {
            HStack(spacing: 6) {
                Text("")
                    .font(.system(size: 24))
                    .foregroundColor(Color(red: 1, green: 0.84, blue: 0))
                Text(String(format: "%.1f", value))
                    .font(.system(size: 22))
                    .foregroundColor(.white)
            }
        } else {
            let scorePercent = Int(value)
            let iconName = RatingIconProvider.getIcon(source: source, scorePercent: scorePercent)
            let formatted = formatMediaBarRating(source: source, value: value)

            HStack(spacing: 8) {
                if let iconName {
                    Image(iconName).resizable().aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
                }
                Text(formatted)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
            }
        }
    }

    private func formatMediaBarRating(source: String, value: Float) -> String {
        switch source {
        case "tomatoes", "popcorn", "tmdb", "metacritic", "metacriticuser", "trakt", "anilist":
            return "\(Int(value))%"
        default:
            return String(format: "%.1f", value)
        }
    }
}

struct RatingsFlowView: View {
    let ratings: [(String, Float)]
    let showLabels: Bool
    let enableAdditionalRatings: Bool
    let isEpisode: Bool
    let enableEpisodeRatings: Bool
    let episodeRating: Float?

    var body: some View {
        let filtered = ratings.filter { source, _ in
            if source == "tmdb_episode" && !(enableEpisodeRatings && isEpisode) { return false }
            if source == "tmdb" && isEpisode && enableEpisodeRatings && episodeRating != nil { return false }
            if !enableAdditionalRatings && source != "tmdb_episode" && source != "tomatoes" { return false }
            return true
        }

        if !filtered.isEmpty {
            HStack(spacing: 8) {
                ForEach(filtered, id: \.0) { source, value in
                    RatingChipView(source: source, normalizedValue: value, showLabel: showLabels)
                }
            }
        }
    }
}

struct CompactRatingsFlowView: View {
    let ratings: [(String, Float)]
    let enableAdditionalRatings: Bool

    var body: some View {
        let filtered = ratings.filter { source, _ in
            if !enableAdditionalRatings && source != "tomatoes" { return false }
            return true
        }

        if !filtered.isEmpty {
            HStack(spacing: 6) {
                ForEach(filtered, id: \.0) { source, value in
                    CompactRatingChipView(source: source, normalizedValue: value)
                }
            }
        }
    }
}

struct MediaBarRatingsRow: View {
    let ratings: [(String, Float)]
    let enableAdditionalRatings: Bool

    var body: some View {
        let filtered = ratings.filter { source, _ in
            if !enableAdditionalRatings && source != "stars" && source != "tomatoes" { return false }
            return true
        }

        if !filtered.isEmpty {
            HStack(spacing: 20) {
                ForEach(filtered, id: \.0) { source, value in
                    MediaBarRatingRow(source: source, value: value)
                }
            }
        }
    }
}
