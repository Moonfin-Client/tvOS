import SwiftUI
import Nuke

struct SearchScreen: View {
    @StateObject private var viewModel: SearchViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    init(container: AppContainer, query: String? = nil) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(
            container: container, initialQuery: query
        ))
    }

    var body: some View {
        ZStack {
            backdropLayer
            overlayLayer

            VStack(spacing: 0) {
                searchHeader
                    .padding(.horizontal, 60)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                searchResults
            }
        }
        .ignoresSafeArea()
        .onAppear {
            router.hideNavbar = true
            if !viewModel.query.isEmpty {
                viewModel.searchImmediately()
            }
        }
    }

    // MARK: - Header

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ToolbarIconButton(
                    systemImage: "house",
                    isActive: false,
                    theme: theme,
                    action: { router.navigate(to: .home) }
                )

                searchField
            }

            focusedItemInfo
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.5))

            TextField("Search...", text: $viewModel.query)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: viewModel.query) { _ in
                    viewModel.searchDebounced()
                }
                .onSubmit {
                    viewModel.searchImmediately()
                }

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.searchDebounced()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(CleanButtonStyle())
            }

            if viewModel.isSearching {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.medium)
                .fill(Color.white.opacity(0.08))
        )
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

    // MARK: - Results

    private var searchResults: some View {
        let trimmedQuery = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if trimmedQuery.isEmpty {
                emptyState
            } else if !viewModel.isSearching && viewModel.resultGroups.isEmpty {
                noResults
            } else {
                resultRows
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))
            Text("Search your library")
                .font(.bodyLg)
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))
            Text("No results found")
                .font(.bodyLg)
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var resultRows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.resultGroups) { group in
                    searchResultRow(group: group)
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func searchResultRow(group: SearchResultGroup) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            HStack(spacing: 6) {
                Text(group.title)
                    .font(.bodyLg)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.colorScheme.onBackground)

                Text("(\(group.items.count))")
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(group.items) { item in
                        SearchResultCard(
                            item: item,
                            imageUrl: viewModel.posterUrl(for: item),
                            subtitle: viewModel.subtitle(for: item),
                            theme: theme,
                            onFocused: { viewModel.setFocusedItem(item) },
                            onTap: { navigateToItem(item) }
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 6)
            }
        }
    }

    private func navigateToItem(_ item: ServerItem) {
        if item.type == .audio, let albumId = item.albumId {
            router.navigate(to: .itemDetails(itemId: albumId, serverId: item.serverId))
        } else {
            router.navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId))
        }
    }

    // MARK: - Background

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
        let alpha = hasBackdrop ? 0.5 : 0.75
        return Color(red: 0.063, green: 0.082, blue: 0.157)
            .opacity(alpha)
            .ignoresSafeArea()
    }
}

// MARK: - Search Result Card

private struct SearchResultCard: View {
    let item: ServerItem
    let imageUrl: String?
    let subtitle: String
    let theme: MoonfinTheme
    let onFocused: () -> Void
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

    private var aspectRatio: CGFloat { item.type.defaultAspectRatio }
    private var cardWidth: CGFloat { item.type.defaultCardWidth }
    private var cardHeight: CGFloat { cardWidth / aspectRatio }
    private var isCircle: Bool { item.type == .person }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    cardImage
                    cardOverlays
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(
                    RoundedRectangle(cornerRadius: isCircle ? cardWidth / 2 : RadiusTokens.small)
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
        .buttonStyle(SearchCardButtonStyle(isFocused: isFocused))
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
        case .musicArtist, .person: return "person.fill"
        case .playlist: return "music.note.list"
        case .photo, .photoAlbum: return "photo"
        case .boxSet: return "square.stack"
        default: return "square.grid.2x2"
        }
    }

    @ViewBuilder
    private var cardOverlays: some View {
        ZStack {
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
            }

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
        .frame(width: cardWidth, height: cardHeight)
    }
}

private struct SearchCardButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .opacity(isFocused ? 1.0 : 0.75)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
