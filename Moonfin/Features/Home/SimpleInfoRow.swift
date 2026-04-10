import SwiftUI

struct SimpleInfoRow: View {
    let item: ServerItem?
    var metadataSummary: String?
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
            .font(.bodyLg)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
    }

    private func metadataParts(for item: ServerItem) -> [AnyView] {
        if let summary = metadataSummary, !summary.isEmpty {
            return summary.components(separatedBy: " \u{2022} ").map { infoText($0) }
        }
        switch item.type {
        case .musicAlbum, .audio, .playlist:
            return musicMetadataParts(for: item)
        default:
            return defaultMetadataParts(for: item)
        }
    }

    private func musicMetadataParts(for item: ServerItem) -> [AnyView] {
        var parts: [AnyView] = []

        let albumArtists = item.albumArtists?
            .compactMap(\.name)
            .joined(separator: ", ")
        let artists = item.artists?.joined(separator: ", ")
        let artistCandidates: [String?] = [albumArtists, item.albumArtist, artists]
        let artist = artistCandidates
            .compactMap { candidate -> String? in
                guard let candidate, !candidate.isEmpty else { return nil }
                return candidate
            }
            .first
        if let artist, !artist.isEmpty {
            parts.append(infoText(artist))
        }

        if let year = yearText(for: item) {
            parts.append(infoText(year))
        }

        if let count = item.songCount ?? item.childCount, count > 0 {
            parts.append(infoText("\(count) track\(count == 1 ? "" : "s")"))
        }

        if let genres = item.genres, !genres.isEmpty {
            parts.append(infoText(genres.prefix(3).joined(separator: ", ")))
        }

        return parts
    }

    private func defaultMetadataParts(for item: ServerItem) -> [AnyView] {
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
            return "S\(s):E\(e)"
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
                .font(.bodyLg)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
        )
    }

    private func ratingBadge(_ rating: String) -> AnyView {
        AnyView(
            Text(rating)
                .font(.bodyLg)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                .padding(.horizontal, SpaceTokens.spaceSm)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                        .stroke(theme.colorScheme.onBackground.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func resolutionBadge(_ resolution: String) -> AnyView {
        AnyView(
            Text(resolution)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                .padding(.horizontal, SpaceTokens.spaceSm)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                        .stroke(theme.colorScheme.onBackground.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
