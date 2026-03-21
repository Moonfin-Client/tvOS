import SwiftUI
import Nuke

struct MusicBrowseScreen: View {
    @StateObject private var viewModel: MusicBrowseViewModel
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    init(container: AppContainer, parentId: String, serverId: String? = nil) {
        _viewModel = StateObject(wrappedValue: MusicBrowseViewModel(
            container: container, parentId: parentId, serverId: serverId
        ))
    }

    var body: some View {
        ZStack {
            backdropLayer
            overlayLayer

            VStack(spacing: 0) {
                musicHeader
                    .padding(.horizontal, 60)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                if viewModel.isLoading && viewModel.rows.allSatisfy({ $0.isLoading }) {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                } else {
                    musicContent
                }

                statusBar
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.initialize()
            router.hideNavbar = true
        }
        .onDisappear {
            router.hideNavbar = false
        }
    }

    // MARK: - Header

    private var musicHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Text(viewModel.libraryName.isEmpty ? "Music" : viewModel.libraryName)
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(.white)
                Spacer()
            }

            focusedItemHud

            HStack(spacing: 4) {
                ToolbarIconButton(
                    systemImage: "house",
                    isActive: false,
                    theme: theme,
                    action: { router.goBack() }
                )
            }
        }
    }

    private var focusedItemHud: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item = viewModel.focusedItem {
                Text(item.name)
                    .font(.system(size: 22, weight: .semibold))
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
        .frame(height: 56, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var musicViewsRow: some View {
        FocusFirstRow(firstItemId: "view_albums") { focusBinding in
            LazyHStack(spacing: 12) {
                MusicViewButton(
                    icon: "opticaldisc",
                    label: "Albums",
                    theme: theme,
                    focusBinding: focusBinding,
                    focusId: "view_albums"
                ) {
                    router.navigate(to: .libraryBrowserByType(
                        itemId: viewModel.parentId, includeType: ItemType.musicAlbum.rawValue
                    ))
                }

                MusicViewButton(
                    icon: "person.2",
                    label: "Album Artists",
                    theme: theme,
                    focusBinding: focusBinding,
                    focusId: "view_album_artists"
                ) {
                    router.navigate(to: .libraryBrowserByType(
                        itemId: viewModel.parentId, includeType: ItemType.albumArtist.rawValue
                    ))
                }

                MusicViewButton(
                    icon: "person",
                    label: "Artists",
                    theme: theme,
                    focusBinding: focusBinding,
                    focusId: "view_artists"
                ) {
                    router.navigate(to: .libraryBrowserByType(
                        itemId: viewModel.parentId, includeType: ItemType.musicArtist.rawValue
                    ))
                }

                MusicViewButton(
                    icon: "theatermasks",
                    label: "Genres",
                    theme: theme,
                    focusBinding: focusBinding,
                    focusId: "view_genres"
                ) {
                    router.navigate(to: .libraryByGenres(
                        itemId: viewModel.parentId, includeType: ItemType.musicAlbum.rawValue
                    ))
                }

                MusicViewButton(
                    icon: "shuffle",
                    label: "Random Album",
                    isAssetIcon: true,
                    theme: theme,
                    focusBinding: focusBinding,
                    focusId: "view_random_album"
                ) {
                    Task {
                        if let albumId = await viewModel.fetchRandomAlbumId() {
                            router.navigate(to: .itemDetails(itemId: albumId, serverId: nil))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, 12)
            .padding(.trailing, 2)
        }
    }

    // MARK: - Content

    private var musicContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Views")
                        .font(.bodyLg)
                        .fontWeight(.semibold)
                        .foregroundColor(theme.colorScheme.onBackground)

                    musicViewsRow
                }

                ForEach(viewModel.rows) { row in
                    if row.isLoading {
                        musicLoadingRow(title: row.title)
                    } else if !row.items.isEmpty {
                        musicItemRow(row: row)
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func musicLoadingRow(title: String) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(title)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .fill(theme.colorScheme.surface.opacity(0.2))
                            .frame(width: 160, height: 160)
                            .shimmering()
                    }
                }
            }
        }
    }

    private func musicItemRow(row: MusicRow) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(row.title)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)

            FocusFirstRow(firstItemId: row.items.first?.id) { focusBinding in
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        MusicSquareCard(
                            item: item,
                            imageUrl: viewModel.squareImageUrl(for: item),
                            subtitle: viewModel.subtitle(for: item),
                            theme: theme,
                            focusBinding: focusBinding,
                            focusId: item.id,
                            onFocused: { viewModel.setFocusedItem(item) },
                            onTap: { handleItemSelection(item: item, rowItems: row.items, index: index) }
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 12)
                .padding(.trailing, 2)
            }
        }
    }

    // MARK: - Navigation

    private func handleItemSelection(item: ServerItem, rowItems: [ServerItem], index: Int) {
        if item.type == .audio {
            let playableItems = rowItems.filter { $0.type == .audio }
            guard !playableItems.isEmpty else {
                navigateToItem(item)
                return
            }

            let startIndex = playableItems.firstIndex(where: { $0.id == item.id }) ?? max(0, index)
            Task {
                await container.playbackCoordinator.startAudioPlayback(items: playableItems, startIndex: startIndex)
                router.navigate(to: .nowPlaying)
            }
            return
        }

        navigateToItem(item)
    }

    private func navigateToItem(_ item: ServerItem) {
        if item.type == .audio, let albumId = item.albumId {
            router.navigate(to: .itemDetails(itemId: albumId, serverId: item.serverId))
        } else {
            router.navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId))
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            let totalItems = viewModel.rows.reduce(0) { $0 + $1.items.count }
            Text("\(totalItems) items across \(viewModel.rows.filter { !$0.items.isEmpty }.count) sections")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 4)
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
        let alpha = hasBackdrop ? 0.45 : 0.75
        return Color(red: 0.063, green: 0.082, blue: 0.157)
            .opacity(alpha)
            .ignoresSafeArea()
    }
}

// MARK: - Music Square Card

private struct MusicSquareCard: View {
    let item: ServerItem
    let imageUrl: String?
    let subtitle: String
    let theme: MoonfinTheme
    let focusBinding: FocusState<String?>.Binding
    let focusId: String
    let onFocused: () -> Void
    let onTap: () -> Void

    private let cardSize: CGFloat = 160

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
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
                    } else {
                        cardPlaceholder
                    }
                }
                .frame(width: cardSize, height: cardSize)
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.extraSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                        .stroke(isFocused ? Color.white : Color.clear, lineWidth: isFocused ? 3 : 0)
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
            .frame(width: cardSize)
        }
        .buttonStyle(MusicCardButtonStyle(isFocused: isFocused))
        .focused(focusBinding, equals: focusId)
        .onChange(of: focusBinding.wrappedValue) { focused in
            if focused == focusId { onFocused() }
        }
    }

    private var isFocused: Bool {
        focusBinding.wrappedValue == focusId
    }

    private var cardPlaceholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: cardSize, height: cardSize)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.2))
            )
    }
}

private struct MusicCardButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .opacity(isFocused ? 1.0 : 0.75)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Music View Button

private struct MusicViewButton: View {
    let icon: String
    let label: String
    var isAssetIcon: Bool = false
    let theme: MoonfinTheme
    let focusBinding: FocusState<String?>.Binding
    let focusId: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if isAssetIcon {
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 30, weight: .medium))
                    }
                }
                .foregroundColor(.white.opacity(isFocused ? 1.0 : 0.75))

                Text(label)
                    .font(.bodySm)
                    .fontWeight(isFocused ? .semibold : .regular)
                    .foregroundColor(.white.opacity(isFocused ? 1.0 : 0.75))
                    .lineLimit(1)
            }
            .frame(width: 170, height: 92)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(Color.white.opacity(isFocused ? 0.22 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .stroke(isFocused ? Color.white : Color.clear, lineWidth: isFocused ? 3 : 0)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused(focusBinding, equals: focusId)
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var isFocused: Bool {
        focusBinding.wrappedValue == focusId
    }
}
