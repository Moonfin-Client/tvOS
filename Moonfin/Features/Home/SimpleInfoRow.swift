import SwiftUI

struct SimpleInfoRow: View {
    let item: ServerItem?
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        if let item {
            HStack(spacing: SpaceTokens.spaceSm) {
                ForEach(Array(metadataParts(for: item).enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        separator
                    }
                    part
                }
            }
        }
    }

    private var separator: some View {
        Text("•")
            .font(.captionXs)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
    }

    private func metadataParts(for item: ServerItem) -> [AnyView] {
        var parts: [AnyView] = []

        if let year = yearText(for: item) {
            parts.append(infoText(year))
        }

        if let seasonEpisode = seasonEpisodeText(for: item) {
            parts.append(infoText(seasonEpisode))
        }

        if let rating = item.officialRating, !rating.isEmpty {
            parts.append(ratingBadge(rating))
        }

        if let runtime = runtimeText(for: item) {
            parts.append(infoText(runtime))
        }

        if let resolution = ResolutionHelper.resolutionName(for: item) {
            parts.append(resolutionBadge(resolution))
        }

        if let communityRating = item.communityRating, communityRating > 0 {
            parts.append(ratingStarView(communityRating))
        }

        if let criticRating = item.criticRating, criticRating > 0 {
            parts.append(criticRatingView(criticRating))
        }

        if let genres = item.genres, !genres.isEmpty {
            parts.append(infoText(genres.prefix(3).joined(separator: ", ")))
        }

        return parts
    }

    private func yearText(for item: ServerItem) -> String? {
        if let year = item.productionYear, year > 0 {
            return String(year)
        }
        if let date = item.premiereDate {
            return String(Calendar.current.component(.year, from: date))
        }
        return nil
    }

    private func seasonEpisodeText(for item: ServerItem) -> String? {
        guard item.type == .episode else { return nil }
        if let s = item.parentIndexNumber, let e = item.indexNumber {
            return "S\(s)E\(e)"
        } else if let e = item.indexNumber {
            return "E\(e)"
        }
        return nil
    }

    private func runtimeText(for item: ServerItem) -> String? {
        guard let ticks = item.runTimeTicks, ticks > 0 else { return nil }
        return RuntimeFormatter.format(ticks: ticks)
    }

    private func infoText(_ text: String) -> AnyView {
        AnyView(
            Text(text)
                .font(.captionXs)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
        )
    }

    private func ratingBadge(_ rating: String) -> AnyView {
        AnyView(
            Text(rating)
                .font(.captionXs)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                .padding(.horizontal, SpaceTokens.spaceXs)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                        .stroke(theme.colorScheme.onBackground.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func resolutionBadge(_ resolution: String) -> AnyView {
        AnyView(
            Text(resolution)
                .font(.captionXs)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                .padding(.horizontal, SpaceTokens.spaceXs)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                        .stroke(theme.colorScheme.onBackground.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func ratingStarView(_ rating: Double) -> AnyView {
        AnyView(
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.colorYellow500)
                Text(String(format: "%.1f", rating))
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
            }
        )
    }

    private func criticRatingView(_ rating: Double) -> AnyView {
        let isFresh = rating >= 60
        return AnyView(
            HStack(spacing: 2) {
                Image(systemName: isFresh ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isFresh ? .colorGreen500 : .colorRed500)
                Text("\(Int(rating))%")
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
            }
        )
    }
}
