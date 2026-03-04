import SwiftUI

struct ContentRow: View {
    let row: HomeRow
    let viewModel: HomeViewModel
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        if row.isLoading {
            loadingRow
        } else if !row.items.isEmpty {
            itemRow
        }
    }

    private var loadingRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(row.title)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .fill(theme.colorScheme.surface.opacity(0.2))
                            .aspectRatio(row.rowType.aspectRatio, contentMode: .fit)
                            .frame(width: row.rowType.cardWidth)
                            .shimmering()
                    }
                }
            }
        }
    }

    private var itemRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(row.title)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        ItemCard(
                            item: item,
                            rowType: row.rowType,
                            viewModel: viewModel
                        )
                        .onAppear {
                            viewModel.loadMoreIfNeeded(row: row, currentIndex: index)
                        }
                    }
                }
            }
        }
    }

}

struct ItemCard: View {
    let item: ServerItem
    let rowType: HomeRowType
    let viewModel: HomeViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private var imageUrl: String? {
        switch rowType {
        case .continueWatching, .nextUp, .liveTv:
            return viewModel.thumbImageUrl(for: item)
        default:
            return viewModel.posterImageUrl(for: item)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            ZStack(alignment: .bottomLeading) {
                cardImage
                overlays
            }
            .frame(width: rowType.cardWidth, height: rowType.cardWidth / rowType.aspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .stroke(isFocused ? theme.accent : .clear, lineWidth: isFocused ? 3 : 0)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { focused in
                if focused { viewModel.onItemFocused(item) }
            }

            cardLabel
        }
    }

    private var cardImage: some View {
        Group {
            if let urlString = imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderContent
                    case .empty:
                        placeholderContent
                    @unknown default:
                        placeholderContent
                    }
                }
            } else {
                placeholderContent
            }
        }
        .frame(width: rowType.cardWidth, height: rowType.cardWidth / rowType.aspectRatio)
    }

    private var placeholderContent: some View {
        ZStack {
            Rectangle().fill(theme.colorScheme.surface.opacity(0.3))
            if rowType == .libraryTiles {
                Image(systemName: libraryIcon)
                    .font(.system(size: 36))
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            }
        }
    }

    private var overlays: some View {
        ZStack(alignment: .bottomLeading) {
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

            if let played = item.userData?.played, played {
                HStack {
                    Spacer()
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2xs)
                            .foregroundColor(.colorGreen500)
                            .padding(4)
                        Spacer()
                    }
                }
            }

            if let isFav = item.userData?.isFavorite, isFav {
                VStack {
                    Image(systemName: "heart.fill")
                        .font(.caption2xs)
                        .foregroundColor(.colorRed300)
                        .padding(4)
                    Spacer()
                }
            }

            if let count = item.userData?.unplayedItemCount, count > 0 {
                HStack {
                    Spacer()
                    VStack {
                        Text("\(count)")
                            .font(.caption2xs)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.accent)
                            .clipShape(Capsule())
                            .padding(4)
                        Spacer()
                    }
                }
            }
        }
    }

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(.captionXs)
                .foregroundColor(theme.colorScheme.onBackground)
                .lineLimit(1)

            if let subtitle = cardSubtitle {
                Text(subtitle)
                    .font(.caption2xs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .frame(width: rowType.cardWidth, alignment: .leading)
    }

    private var cardSubtitle: String? {
        switch item.type {
        case .episode:
            if let s = item.parentIndexNumber, let e = item.indexNumber {
                return "S\(s)E\(e)"
            }
            return item.seriesName
        case .series, .movie:
            return item.productionYear.map(String.init)
        case .musicAlbum:
            return nil
        case .playlist:
            if let count = item.userData?.unplayedItemCount {
                return "\(count) items"
            }
            return nil
        default:
            return nil
        }
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

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, phase - 0.3)),
                        .init(color: .white.opacity(0.1), location: phase),
                        .init(color: .clear, location: min(1, phase + 0.3)),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
