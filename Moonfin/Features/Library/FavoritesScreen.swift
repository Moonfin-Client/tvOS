import SwiftUI
import Nuke

struct FavoritesScreen: View {
    @StateObject private var viewModel: FavoritesViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: FavoritesViewModel(container: container))
    }

    var body: some View {
        ZStack {
            backdropLayer
            overlayLayer

            VStack(spacing: 0) {
                screenHeader
                    .padding(.horizontal, 60)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                if viewModel.isLoading && viewModel.sections.isEmpty {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if viewModel.sections.isEmpty {
                    emptyState
                } else {
                    sectionRows
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            router.pushNavbarHidden()
            viewModel.initialize()
        }
        .onDisappear {
            router.popNavbarHidden()
        }
    }

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ToolbarIconButton(
                    systemImage: "house",
                    isActive: false,
                    theme: theme,
                    action: { router.goBack() }
                )

                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.colorRed300)
                    Text("Favorites")
                        .font(.titleXl)
                        .foregroundColor(.white)
                }

                Spacer()
            }

            focusedItemInfo
        }
    }

    private var focusedItemInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item = viewModel.focusedItem {
                Text(item.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                let sub = viewModel.subtitle(for: item)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.bodySm)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .frame(height: 50, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))
            Text("No favorites yet")
                .font(.bodyLg)
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var sectionRows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.sections) { section in
                    favoriteRow(section: section)
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func favoriteRow(section: FavoriteSection) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            HStack(spacing: 6) {
                Text(section.title)
                    .font(.bodyLg)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.colorScheme.onBackground)

                Text("(\(section.items.count))")
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(section.items) { item in
                        BrowseItemCard(
                            item: item,
                            imageUrl: viewModel.posterUrl(for: item),
                            subtitle: viewModel.subtitle(for: item),
                            theme: theme,
                            onFocused: { viewModel.setFocusedItem(item) },
                            onTap: { router.navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId)) }
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 6)
            }
        }
    }

    private var backdropLayer: some View {
        GeometryReader { geo in
            if viewModel.backgroundService.enabled,
               let urlString = viewModel.backgroundService.currentBackdropUrl,
               let url = URL(string: urlString) {
                CachedImage(
                    url: url,
                    processors: [
                        ImageProcessors.Resize(size: CGSize(width: geo.size.width, height: geo.size.height), contentMode: .aspectFill),
                        ImageProcessors.GaussianBlur(radius: Int(viewModel.backgroundService.blurAmount))
                    ]
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .drawingGroup()
                .transition(.opacity)
                .id(urlString)
            }
        }
        .animation(.easeInOut(duration: BackgroundService.transitionDuration), value: viewModel.backgroundService.currentBackdropUrl)
        .background(theme.colorScheme.background)
    }

    private var overlayLayer: some View {
        let hasBackdrop = viewModel.backgroundService.currentBackdropUrl != nil
        return Color(red: 0.063, green: 0.082, blue: 0.157)
            .opacity(hasBackdrop ? 0.5 : 0.75)
            .ignoresSafeArea()
    }
}

struct BrowseItemCard: View {
    let item: ServerItem
    let imageUrl: String?
    let subtitle: String
    let theme: MoonfinTheme
    let onFocused: () -> Void
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

    private var cardWidth: CGFloat { item.type.defaultCardWidth }
    private var cardHeight: CGFloat { cardWidth / item.type.defaultAspectRatio }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    cardImage
                    progressOverlay
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(
                    item.type == .person
                        ? AnyShape(Circle())
                        : AnyShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                )

                Text(item.name)
                    .font(.captionXs)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth)
        }
        .buttonStyle(BrowseCardButtonStyle(isFocused: isFocused))
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused() }
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
                    cardPlaceholder
                default:
                    cardPlaceholder.shimmering()
                }
            }
            .frame(width: cardWidth, height: cardHeight)
        } else {
            cardPlaceholder
        }
    }

    private var cardPlaceholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: cardWidth, height: cardHeight)
            .overlay(
                Image(systemName: placeholderIcon)
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.2))
            )
    }

    private var placeholderIcon: String {
        switch item.type {
        case .movie, .video: return "film"
        case .series: return "tv"
        case .episode: return "play.rectangle"
        case .audio: return "music.note"
        case .musicAlbum: return "opticaldisc"
        case .person, .musicArtist: return "person.fill"
        case .playlist: return "music.note.list"
        default: return "square.grid.2x2"
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if let progress = item.userData?.playedPercentage, progress > 0 {
            VStack {
                Spacer()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.black.opacity(0.5)).frame(height: 4)
                        Rectangle().fill(theme.accent).frame(
                            width: geo.size.width * CGFloat(progress / 100.0), height: 4
                        )
                    }
                }
                .frame(height: 4)
            }
            .frame(width: cardWidth, height: cardHeight)
        }
    }
}

struct BrowseCardButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .opacity(isFocused ? 1.0 : 0.75)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
