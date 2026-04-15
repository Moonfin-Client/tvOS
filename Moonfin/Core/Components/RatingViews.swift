import SwiftUI

private struct RatingChipHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct EqualHeightRatingRow<Content: View>: View {
    let spacing: CGFloat
    let content: (CGFloat?) -> Content

    @State private var sharedHeight: CGFloat?

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            content(sharedHeight)
        }
        .onPreferenceChange(RatingChipHeightPreferenceKey.self) { measuredHeight in
            sharedHeight = measuredHeight > 0 ? measuredHeight : nil
        }
    }
}

private struct BaseRatingChipView<Icon: View>: View {
    let valueText: String
    let labelText: String?
    let sharedHeight: CGFloat?
    let icon: Icon

    init(valueText: String, labelText: String?, sharedHeight: CGFloat?, @ViewBuilder icon: () -> Icon) {
        self.valueText = valueText
        self.labelText = labelText
        self.sharedHeight = sharedHeight
        self.icon = icon()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                icon
                Text(valueText)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            if let labelText {
                Text(labelText)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: sharedHeight)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: RatingChipHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}

struct RatingChipView: View {
    let source: String
    let normalizedValue: Float
    let showLabel: Bool
    let sharedHeight: CGFloat? = nil

    var body: some View {
        let scorePercent = Int(normalizedValue * 100)
        if let iconName = RatingIconProvider.getIcon(source: source, scorePercent: scorePercent) {
            let ratingSource = RatingSource(rawValue: source)
            let formatted = ratingSource?.format(normalizedValue) ?? "\(scorePercent)%"
            let label = ratingSource?.label ?? source

            BaseRatingChipView(valueText: formatted, labelText: showLabel ? label : nil, sharedHeight: sharedHeight) {
                Image(iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
            }
        }
    }
}

struct StarRatingChipView: View {
    let value: Float
    let showLabel: Bool
    let sharedHeight: CGFloat? = nil

    var body: some View {
        BaseRatingChipView(valueText: String(format: "%.1f", value), labelText: showLabel ? Strings.communityRating : nil, sharedHeight: sharedHeight) {
            Image(systemName: "star.fill")
                .font(.system(size: 30))
                .foregroundColor(Color(red: 1, green: 0.84, blue: 0))
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
            HStack(spacing: 4) {
                Text("★")
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 1, green: 0.84, blue: 0))
                Text(String(format: "%.1f", value))
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .fixedSize()
            }
        } else {
            let scorePercent = Int(value * 100)
            let iconName = RatingIconProvider.getIcon(source: source, scorePercent: scorePercent)
            let formatted = RatingSource(rawValue: source)?.format(value) ?? "\(scorePercent)%"

            HStack(spacing: 4) {
                if let iconName {
                    Image(iconName).resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
                }
                Text(formatted)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .fixedSize()
            }
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
            EqualHeightRatingRow(spacing: 8) { sharedHeight in
                ForEach(filtered, id: \.0) { source, value in
                    RatingChipView(source: source, normalizedValue: value, showLabel: showLabels, sharedHeight: sharedHeight)
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
            if !enableAdditionalRatings && source != "stars" && source != "tomatoes" && source != "tmdb_episode" { return false }
            return true
        }

        if !filtered.isEmpty {
            HStack(spacing: 16) {
                ForEach(filtered, id: \.0) { source, value in
                    MediaBarRatingRow(source: source, value: value)
                }
            }
        }
    }
}
