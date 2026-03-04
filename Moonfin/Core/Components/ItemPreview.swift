import SwiftUI

struct ItemPreview: View {
    let item: ServerItem
    let imageUrl: String?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var cardWidth: CGFloat = 150
    var shape: CardShape = .rounded
    var watchedIndicator: WatchedIndicatorBehavior = .always
    var onFocused: ((ServerItem) -> Void)?

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            ItemCard(
                item: item,
                imageUrl: imageUrl,
                aspectRatio: aspectRatio,
                cardWidth: cardWidth,
                shape: shape,
                watchedIndicator: watchedIndicator,
                onFocused: onFocused
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2xs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
    }

    private var subtitle: String? {
        switch item.type {
        case .episode:
            if let s = item.parentIndexNumber, let e = item.indexNumber {
                return "S\(s)E\(e)"
            }
            return item.seriesName
        case .series, .movie:
            return item.productionYear.map(String.init)
        case .musicAlbum:
            return item.genres?.first
        case .playlist:
            if let count = item.userData?.unplayedItemCount {
                return "\(count) items"
            }
            return nil
        case .season:
            return item.seriesName
        case .person:
            return nil
        default:
            return item.productionYear.map(String.init)
        }
    }
}
