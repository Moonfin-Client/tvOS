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
    var serverName: String?
    var onFocused: ((ServerItem) -> Void)?
    var onSelect: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)? = nil
    var onToggleWatched: (() -> Void)?
    var onToggleFavorite: (() -> Void)?

    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var previewManager: PreviewPlayerManager
    @FocusState private var isFocused: Bool

    private var cardHeight: CGFloat { cardWidth / aspectRatio }

    private var cornerRadius: CGFloat {
        shape == .circle ? cardWidth / 2 : RadiusTokens.small
    }

    var body: some View {
        Button(action: { onSelect?() }) {
            ZStack(alignment: .bottomLeading) {
                cardImage
                
                if shouldShowPreview {
                    MediaPreviewOverlay(
                        item: item,
                        shouldPlay: isFocused,
                        muted: !previewAudioEnabled
                    )
                }
                
                cardOverlays
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(ItemCardButtonStyle(
            isFocused: isFocused,
            cornerRadius: cornerRadius,
            focusBorderColor: theme.focusBorder.color
        ))
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused {
                onFocused?(item)
                if !shouldShowPreview {
                    previewManager.stop()
                }
            }
            onFocusChange?(focused)
        }
        .contextMenu {
            if let onToggleWatched {
                Button {
                    onToggleWatched()
                } label: {
                    Label(
                        item.userData?.played == true ? Strings.markUnwatched : Strings.markWatched,
                        systemImage: item.userData?.played == true ? "eye.slash" : "checkmark.circle"
                    )
                }
            }
            if let onToggleFavorite {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(
                        item.userData?.isFavorite == true ? Strings.removeFavorite : Strings.addFavorite,
                        systemImage: item.userData?.isFavorite == true ? "heart.slash" : "heart"
                    )
                }
            }
        }
    }
    
    private var shouldShowPreview: Bool {
        guard previewEnabled else { return false }
        switch item.type {
        case .episode, .season, .series, .movie, .trailer, .video:
            return true
        default:
            return false
        }
    }

    private var previewEnabled: Bool {
        container.userPreferences[UserPreferences.mediaPreviewEnabled]
    }
    
    private var previewAudioEnabled: Bool {
        container.userPreferences[UserPreferences.previewAudioEnabled]
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
            serverBadgeOverlay
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
        if watchedIndicator != .never,
           watchedIndicator != .episodesOnly || item.type == .episode {
            VStack {
                HStack {
                    Spacer()
                    if watchedIndicator == .always || watchedIndicator == .episodesOnly,
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

    @ViewBuilder
    private var serverBadgeOverlay: some View {
        if let name = serverName, !name.isEmpty {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
        }
    }
}

struct ItemCardButtonStyle: ButtonStyle {
    let isFocused: Bool
    let cornerRadius: CGFloat
    let focusBorderColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? focusBorderColor : .clear, lineWidth: isFocused ? 3 : 0)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
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
