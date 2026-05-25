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

    @EnvironmentObject var theme: MoonfinTheme

    init(valueText: String, labelText: String?, sharedHeight: CGFloat?, @ViewBuilder icon: () -> Icon) {
        self.valueText = valueText
        self.labelText = labelText
        self.sharedHeight = sharedHeight
        self.icon = icon()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                icon
                Text(valueText)
                    .font(.token(20, weight: .bold))
                    .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white)
            }
            if let labelText {
                Text(labelText)
                    .font(.token(16))
                    .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white.opacity(0.5))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(height: sharedHeight)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: RatingChipHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
        .background(theme.isNeonPulseTheme ? theme.neonSecondaryColor.opacity(0.12) : Color.white.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.isNeonPulseTheme ? theme.neonPrimaryColor.opacity(0.85) : .clear, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

struct RatingChipView: View {
    let source: String
    let normalizedValue: Float
    let showLabel: Bool
    var sharedHeight: CGFloat? = nil

    var body: some View {
        let canonicalSource = RatingSource.canonicalSourceRawValue(source)
        let scorePercent = Int(normalizedValue * 100)
        let iconName = RatingIconProvider.getIcon(source: canonicalSource, scorePercent: scorePercent)
        let ratingSource = RatingSource(rawValue: canonicalSource)
        let formatted = ratingSource?.format(normalizedValue) ?? "\(scorePercent)%"
        let label = ratingSource?.label ?? canonicalSource

        BaseRatingChipView(valueText: formatted, labelText: showLabel ? label : nil, sharedHeight: sharedHeight) {
            if let iconName {
                Image(iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "tag.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}

struct StarRatingChipView: View {
    let value: Float
    let showLabel: Bool
    var sharedHeight: CGFloat? = nil

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

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        let canonicalSource = RatingSource.canonicalSourceRawValue(source)
        let scorePercent = Int(normalizedValue * 100)
        let iconName = RatingIconProvider.getIcon(source: canonicalSource, scorePercent: scorePercent)
        let ratingSource = RatingSource(rawValue: canonicalSource)
        let formatted = ratingSource?.format(normalizedValue) ?? "\(scorePercent)%"

        HStack(spacing: 3) {
            if let iconName {
                Image(iconName).resizable().aspectRatio(contentMode: .fit).frame(width: 16, height: 16)
            } else {
                Image(systemName: "tag.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white.opacity(0.7))
            }

            Text(formatted)
                .font(.token(13, weight: .semibold))
                .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white.opacity(0.7))
        }
    }
}

struct MediaBarRatingRow: View {
    let source: String
    let value: Float

    @EnvironmentObject var theme: MoonfinTheme

    private var borderColor: Color {
        theme.isNeonPulseTheme ? theme.neonPrimaryColor.opacity(0.85) : .clear
    }

    var body: some View {
        Group {
            if RatingSource.canonicalSourceRawValue(source) == RatingSource.communityRawValue {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0))
                    Text(String(format: "%.1f", value))
                        .font(.token(TypographyTokens.fontSizeXs))
                        .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white)
                        .fixedSize()
                }
            } else {
                let canonicalSource = RatingSource.canonicalSourceRawValue(source)
                let scorePercent = Int(value * 100)
                let iconName = RatingIconProvider.getIcon(source: canonicalSource, scorePercent: scorePercent)
                let formatted = RatingSource(rawValue: canonicalSource)?.format(value) ?? "\(scorePercent)%"

                HStack(spacing: 4) {
                    if let iconName {
                        Image(iconName).resizable().aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white)
                    }
                    Text(formatted)
                        .font(.token(TypographyTokens.fontSizeXs))
                        .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                .stroke(borderColor, lineWidth: 1)
        )
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
    @EnvironmentObject var container: AppContainer

    var body: some View {
        let prefs = container.userPreferences
        let showRatingBadges = prefs[UserPreferences.showRatingBadges]

        let enabledSourcesOrdered = RatingSource.canonicalEnabledSourceOrder(prefs[UserPreferences.enabledRatings])
        let hasEpisodeRating = ratings.contains { RatingSource.canonicalSourceRawValue($0.0) == RatingSource.tmdbEpisodeRawValue }

        let filtered = RatingDisplayPolicy.apply(
            ratings: ratings,
            enabledSourcesOrdered: enabledSourcesOrdered,
            enableAdditionalRatings: enableAdditionalRatings,
            isEpisode: hasEpisodeRating,
            enableEpisodeRatings: prefs[UserPreferences.enableEpisodeRatings],
            hasEpisodeRating: hasEpisodeRating
        )

        if showRatingBadges && !filtered.isEmpty {
            HStack(spacing: 16) {
                ForEach(filtered, id: \.0) { source, value in
                    MediaBarRatingRow(source: source, value: value)
                }
            }
        }
    }
}
