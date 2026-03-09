import SwiftUI

struct ItemPreview: View {
    let item: ServerItem
    let imageUrl: String?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var cardWidth: CGFloat = 150
    var shape: CardShape = .rounded
    var watchedIndicator: WatchedIndicatorBehavior = .always
    var onFocused: ((ServerItem) -> Void)?
    var onSelect: (() -> Void)?

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            ItemCard(
                item: item,
                imageUrl: imageUrl,
                aspectRatio: aspectRatio,
                cardWidth: cardWidth,
                shape: shape,
                watchedIndicator: watchedIndicator,
                onFocused: onFocused,
                onSelect: onSelect
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)

                if !subtitleParts.isEmpty {
                    Text(subtitleParts.joined(separator: " • "))
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
    }

    private var subtitleParts: [String] {
        var parts: [String] = []

        switch item.type {
        case .movie:
            parts.append("Movie")
        case .series:
            parts.append("Series")
        case .episode:
            if let s = item.parentIndexNumber, let e = item.indexNumber {
                parts.append("S\(s)E\(e)")
            }
        case .season:
            if let name = item.seriesName {
                parts.append(name)
            }
        case .musicAlbum:
            if let genre = item.genres?.first {
                parts.append(genre)
            }
        case .playlist:
            parts.append("Playlist")
        case .person:
            return []
        default:
            break
        }

        if let year = item.productionYear, year > 0 {
            parts.append(String(year))
        }

        if let resolution = ResolutionHelper.resolutionName(for: item) {
            parts.append(resolution)
        }

        return parts
    }
}
