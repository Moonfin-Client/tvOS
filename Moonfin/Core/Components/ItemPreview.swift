import SwiftUI

struct ItemPreview: View {
    let item: ServerItem
    let imageUrl: String?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var cardWidth: CGFloat = 180
    var shape: CardShape = .rounded
    var watchedIndicator: WatchedIndicatorBehavior = .always
    var serverName: String?
    var showLabels: Bool = true
    var onFocused: ((ServerItem) -> Void)?
    var onSelect: (() -> Void)?
    var onToggleWatched: (() -> Void)?
    var onToggleFavorite: (() -> Void)?

    @EnvironmentObject var theme: MoonfinTheme
    @State private var isCardFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            ItemCard(
                item: item,
                imageUrl: imageUrl,
                aspectRatio: aspectRatio,
                cardWidth: cardWidth,
                shape: shape,
                watchedIndicator: watchedIndicator,
                serverName: serverName,
                onFocused: onFocused,
                onSelect: onSelect,
                onFocusChange: { isCardFocused = $0 },
                onToggleWatched: onToggleWatched,
                onToggleFavorite: onToggleFavorite
            )

            if showLabels {
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: item.name,
                        font: .captionXs,
                        fontSize: TypographyTokens.fontSizeXs,
                        color: theme.colorScheme.listHeadline,
                        maxWidth: cardWidth,
                        isFocused: isCardFocused
                    )

                    if !item.cardSubtitle.isEmpty {
                        MarqueeText(
                            text: item.cardSubtitle,
                            font: .captionXs,
                            fontSize: TypographyTokens.fontSizeXs,
                            color: theme.colorScheme.listCaption,
                            maxWidth: cardWidth,
                            isFocused: isCardFocused
                        )
                    }
                }
                .frame(width: cardWidth, alignment: .leading)
            }
        }
    }
}

extension ServerItem {
    var cardSubtitleParts: [String] {
        var parts: [String] = []

        switch type {
        case .movie:
            if let year = displayYear {
                parts.append(String(year))
            }
            if let resolution = ResolutionHelper.resolutionName(for: self) {
                parts.append(resolution)
            }
        case .episode:
            if let s = parentIndexNumber, let e = indexNumber {
                parts.append("S\(s):E\(e)")
            }
            if let name = seriesName, !name.isEmpty {
                parts.append(name)
            }
            if let year = displayYear {
                parts.append(String(year))
            }
        case .season:
            if let name = seriesName {
                parts.append(name)
            }
            if let year = displayYear {
                parts.append(String(year))
            }
        case .musicAlbum:
            if let genre = genres?.first {
                parts.append(genre)
            }
        case .playlist:
            parts.append("Playlist")
        case .person:
            return []
        case .series:
            if let year = displayYear {
                parts.append(String(year))
            }
            if let rating = officialRating, !rating.isEmpty {
                parts.append(rating)
            }
        default:
            if let year = displayYear {
                parts.append(String(year))
            }
            if let resolution = ResolutionHelper.resolutionName(for: self) {
                parts.append(resolution)
            }
        }

        return parts
    }

    private var displayYear: Int? {
        if let year = productionYear, year > 0 {
            return year
        }
        if let date = premiereDate {
            return Calendar.current.component(.year, from: date)
        }
        return nil
    }

    var cardSubtitle: String {
        cardSubtitleParts.joined(separator: " • ")
    }
}
