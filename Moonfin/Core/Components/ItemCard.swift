import SwiftUI

enum CardShape {
    case rounded
    case circle
}

struct ItemCard: View {
    let item: ServerItem
    let imageUrl: String?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var cardWidth: CGFloat = 150
    var shape: CardShape = .rounded
    var watchedIndicator: WatchedIndicatorBehavior = .always
    var onFocused: ((ServerItem) -> Void)?

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private var cardHeight: CGFloat { cardWidth / aspectRatio }

    private var cornerRadius: CGFloat {
        shape == .circle ? cardWidth / 2 : RadiusTokens.small
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardImage
            cardOverlays
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .focusable()
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused?(item) }
        }
    }

    @ViewBuilder
    private var cardImage: some View {
        if let urlString = imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                case .empty:
                    placeholder.shimmering()
                @unknown default:
                    placeholder
                }
            }
            .frame(width: cardWidth, height: cardHeight)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(theme.colorScheme.surface.opacity(0.3))
            .frame(width: cardWidth, height: cardHeight)
    }

    private var cardOverlays: some View {
        ZStack {
            progressOverlay
            favoriteOverlay
            watchIndicatorOverlay
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if let progress = item.userData?.playedPercentage, progress > 0 {
            VStack {
                Spacer()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(height: 4)
                        Rectangle()
                            .fill(theme.accent)
                            .frame(width: geo.size.width * CGFloat(progress / 100.0), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    @ViewBuilder
    private var favoriteOverlay: some View {
        if let isFav = item.userData?.isFavorite, isFav {
            VStack {
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.caption2xs)
                        .foregroundColor(.colorRed300)
                        .padding(4)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var watchIndicatorOverlay: some View {
        if watchedIndicator != .never {
            VStack {
                HStack {
                    Spacer()
                    if watchedIndicator == .always,
                       let played = item.userData?.played, played {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2xs)
                            .foregroundColor(.colorGreen500)
                            .padding(4)
                    } else if let count = item.userData?.unplayedItemCount, count > 0 {
                        Text("\(count)")
                            .font(.caption2xs)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.accent)
                            .clipShape(Capsule())
                            .padding(4)
                    }
                }
                Spacer()
            }
        }
    }
}

extension ItemType {
    var defaultAspectRatio: CGFloat {
        switch self {
        case .episode, .program, .liveTvProgram:
            return 16.0 / 9.0
        case .musicAlbum, .musicArtist, .audio, .channel, .liveTvChannel, .person:
            return 1.0
        case .userView, .collectionFolder:
            return 16.0 / 9.0
        default:
            return 2.0 / 3.0
        }
    }

    var defaultCardWidth: CGFloat {
        switch self {
        case .episode, .program, .liveTvProgram, .userView, .collectionFolder:
            return 280
        case .musicAlbum, .musicArtist, .audio, .channel, .liveTvChannel, .person:
            return 180
        default:
            return 150
        }
    }
}
