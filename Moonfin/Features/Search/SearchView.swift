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
        .onAppear {
            router.pushNavbarHidden()
            if !viewModel.query.isEmpty {
                viewModel.searchImmediately()
            }
        }
        .onDisappear {
            router.popNavbarHidden()
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
                    action: { router.goBack() }
                )

                searchField
            }

            focusedItemInfo
        }
    }

    private var searchField: some View {
        SearchTextField(
            text: $viewModel.query,
            isLoading: viewModel.isSearching,
            theme: theme,
            onChanged: { viewModel.searchDebounced() },
            onSubmit: { viewModel.searchImmediately() },
            onClear: {
                viewModel.query = ""
                viewModel.searchDebounced()
            }
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
            } else if !viewModel.isSearching && viewModel.resultGroups.isEmpty && viewModel.seerrResults.isEmpty {
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
                if !viewModel.seerrResults.isEmpty {
                    seerrResultRow
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private var seerrResultRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            HStack(spacing: 6) {
                Text("Jellyseerr")
                    .font(.bodyLg)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.colorScheme.onBackground)

                Text("(\(viewModel.seerrResults.count))")
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(viewModel.seerrResults) { item in
                        SeerrSearchCard(item: item, onTap: {
                            guard let data = try? JSONEncoder().encode(item),
                                  let json = String(data: data, encoding: .utf8) else { return }
                            router.navigate(to: .seerrMediaDetails(itemJson: json))
                        })
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 6)
            }
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
        .ignoresSafeArea()
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
                .overlay(
                    RoundedRectangle(cornerRadius: isCircle ? cardWidth / 2 : RadiusTokens.small)
                        .stroke(Color.white, lineWidth: isFocused ? 3 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isFocused)
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

private struct SearchTextField: View {
    @Binding var text: String
    let isLoading: Bool
    let theme: MoonfinTheme
    let onChanged: () -> Void
    let onSubmit: () -> Void
    let onClear: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(isFocused ? theme.colorScheme.onInputFocused : .white.opacity(0.4))

            TextField("Search movies, shows, music...", text: $text)
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(isFocused ? theme.colorScheme.onInputFocused : theme.colorScheme.onInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: text) { _ in onChanged() }
                .onSubmit { onSubmit() }

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            }

            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(isFocused ? .white.opacity(0.6) : .white.opacity(0.3))
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(isFocused ? theme.colorScheme.inputFocused.opacity(0.15) : theme.colorScheme.input.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .stroke(
                    isFocused ? theme.accent.opacity(0.8) : Color.white.opacity(0.06),
                    lineWidth: isFocused ? 2.5 : 1
                )
        )
        .focused($isFocused)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
    }
}

private struct SeerrSearchCard: View {
    let item: SeerrDiscoverItemDto
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat = 150
    private let cardHeight: CGFloat = 225

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let path = item.posterPath, let url = URL(string: SeerrImageUrl.poster(path)) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                            case .failure: placeholder
                            default: placeholder.shimmering()
                            }
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .stroke(Color.white, lineWidth: isFocused ? 3 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isFocused)
                )

                Text(item.displayTitle)
                    .font(.captionXs)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(item.mediaType == "tv" ? "TV Show" : "Movie")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(width: cardWidth)
        }
        .buttonStyle(SearchCardButtonStyle(isFocused: isFocused))
        .focused($isFocused)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: cardWidth, height: cardHeight)
            .overlay(
                Image(systemName: item.mediaType == "tv" ? "tv" : "film")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.2))
            )
    }
}
