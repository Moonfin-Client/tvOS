import SwiftUI

struct LibraryCard: View {
    let item: ServerItem
    let imageUrl: String?
    var cardWidth: CGFloat = 280
    var onFocused: ((ServerItem) -> Void)?
    var onSelect: (() -> Void)?

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let aspectRatio: CGFloat = 16.0 / 9.0
    private var cardHeight: CGFloat { cardWidth / aspectRatio }

    var body: some View {
        Button(action: { onSelect?() }) {
            ZStack {
                cardImage

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.6), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: libraryIcon)
                            .font(.captionXs)
                            .foregroundColor(.white.opacity(0.8))
                        Text(item.name)
                            .font(.captionXs)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(SpaceTokens.spaceSm)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
        }
        .buttonStyle(ItemCardButtonStyle(
            isFocused: isFocused,
            cornerRadius: RadiusTokens.small,
            focusBorderColor: theme.focusBorder.color
        ))
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused?(item) }
        }
    }

    @ViewBuilder
    private var cardImage: some View {
        if imageUrl != nil {
            CachedImage(
                urlString: imageUrl,
                thumbnailSize: CGSize(width: cardWidth, height: cardHeight)
            )
            .frame(width: cardWidth, height: cardHeight)
        } else {
            libraryPlaceholder
        }
    }

    private var libraryPlaceholder: some View {
        ZStack {
            Rectangle().fill(theme.colorScheme.surface.opacity(0.3))
            Image(systemName: libraryIcon)
                .font(.system(size: 36))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private var libraryIcon: String {
        guard let ct = item.collectionType?.lowercased() else { return "folder" }
        switch ct {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "music": return "music.note"
        case "books": return "book"
        case "photos": return "photo"
        case "homevideos": return "video"
        case "boxsets": return "square.stack"
        case "playlists": return "list.bullet"
        case "livetv": return "antenna.radiowaves.left.and.right"
        default: return "folder"
        }
    }
}
