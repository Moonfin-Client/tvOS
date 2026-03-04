import SwiftUI

struct SimpleInfoRow: View {
    let item: ServerItem?
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        if let item {
            HStack(spacing: SpaceTokens.spaceSm) {
                ForEach(Array(metadataParts(for: item).enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Text("•")
                            .font(.captionXs)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
                    }
                    part
                }
            }
        }
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

        if let resolution = resolutionText(for: item) {
            parts.append(resolutionBadge(resolution))
        }

        if let communityRating = item.communityRating, communityRating > 0 {
            parts.append(ratingStarText(communityRating))
        }

        if let criticRating = item.criticRating, criticRating > 0 {
            parts.append(criticRatingText(criticRating))
        }

        if let genres = item.genres, !genres.isEmpty {
            let genreText = genres.prefix(3).joined(separator: ", ")
            parts.append(infoText(genreText))
        }

        return parts
    }

    // MARK: - Text Builders

    private func yearText(for item: ServerItem) -> String? {
        if let year = item.productionYear, year > 0 {
            return String(year)
        }
        if let date = item.premiereDate {
            let calendar = Calendar.current
            return String(calendar.component(.year, from: date))
        }
        return nil
    }

    private func seasonEpisodeText(for item: ServerItem) -> String? {
        guard item.type == .episode else { return nil }
        let season = item.parentIndexNumber
        let episode = item.indexNumber
        if let s = season, let e = episode {
            return "S\(s)E\(e)"
        } else if let e = episode {
            return "E\(e)"
        }
        return nil
    }

    private func runtimeText(for item: ServerItem) -> String? {
        guard let ticks = item.runTimeTicks, ticks > 0 else { return nil }
        let totalMinutes = Int(ticks / 600_000_000)
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(totalMinutes)m"
    }

    private func resolutionText(for item: ServerItem) -> String? {
        guard let streams = item.mediaStreams ?? item.mediaSources?.first?.mediaStreams else { return nil }
        guard let videoStream = streams.first(where: { $0.type == .video }) else { return nil }
        guard let width = videoStream.width else { return nil }

        switch width {
        case 3000...: return "4K"
        case 1800...: return "1080p"
        case 1200...: return "720p"
        case 600...: return "480p"
        default: return nil
        }
    }

    // MARK: - View Builders

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

    private func ratingStarText(_ rating: Double) -> AnyView {
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

    private func criticRatingText(_ rating: Double) -> AnyView {
        AnyView(
            HStack(spacing: 2) {
                Image(systemName: rating >= 60 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(.system(size: 10))
                    .foregroundColor(rating >= 60 ? .colorGreen500 : .colorRed500)
                Text("\(Int(rating))%")
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
            }
        )
    }
}
