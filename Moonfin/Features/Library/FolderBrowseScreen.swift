import SwiftUI
import Nuke

struct FolderBrowseScreen: View {
    @StateObject private var viewModel: FolderBrowseViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    init(container: AppContainer, folderId: String? = nil) {
        _viewModel = StateObject(wrappedValue: FolderBrowseViewModel(
            container: container, folderId: folderId
        ))
    }

    var body: some View {
        ZStack {
            backdropLayer
            overlayLayer

            VStack(spacing: 0) {
                folderHeader
                    .padding(.horizontal, 60)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                if viewModel.isLoading && viewModel.rootRows.isEmpty && viewModel.items.isEmpty {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if viewModel.isRootView {
                    rootFolderRows
                } else {
                    folderGrid
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            router.hideNavbar = true
            viewModel.initialize()
        }
    }

    private var folderHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ToolbarIconButton(
                    systemImage: "house",
                    isActive: false,
                    theme: theme,
                    action: { router.navigate(to: .home) }
                )

                breadcrumbBar
                Spacer()
            }

            focusedItemInfo
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    Task { await viewModel.navigateToRoot() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 16))
                        Text("Folders")
                            .font(.bodySm)
                    }
                    .foregroundColor(viewModel.breadcrumbs.isEmpty ? .white : .white.opacity(0.5))
                }
                .buttonStyle(CleanButtonStyle())

                ForEach(viewModel.breadcrumbs) { crumb in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))

                    Button {
                        Task { await viewModel.navigateToBreadcrumb(crumb) }
                    } label: {
                        Text(crumb.name)
                            .font(.bodySm)
                            .foregroundColor(
                                crumb.id == viewModel.breadcrumbs.last?.id ? .white : .white.opacity(0.5)
                            )
                    }
                    .buttonStyle(CleanButtonStyle())
                }
            }
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

    private var rootFolderRows: some View {
        Group {
            if viewModel.rootRows.isEmpty && !viewModel.isLoading {
                emptyState(icon: "folder", message: "No folders found")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(viewModel.rootRows) { row in
                            folderRowView(row: row)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func folderRowView(row: FolderRow) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            HStack(spacing: 6) {
                Text(row.title)
                    .font(.bodyLg)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.colorScheme.onBackground)

                Text("(\(row.items.count))")
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(row.items) { item in
                        FolderItemCard(
                            item: item,
                            imageUrl: viewModel.posterUrl(for: item),
                            subtitle: viewModel.subtitle(for: item),
                            theme: theme,
                            onFocused: { viewModel.setFocusedItem(item) },
                            onTap: { handleItemTap(item) }
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 6)
            }
        }
    }

    private var folderGrid: some View {
        Group {
            if viewModel.items.isEmpty && !viewModel.isLoading {
                emptyState(icon: "folder", message: "Empty folder")
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 280), spacing: SpaceTokens.spaceMd)],
                        spacing: SpaceTokens.spaceMd
                    ) {
                        ForEach(viewModel.items) { item in
                            FolderItemCard(
                                item: item,
                                imageUrl: viewModel.posterUrl(for: item),
                                subtitle: viewModel.subtitle(for: item),
                                theme: theme,
                                onFocused: { viewModel.setFocusedItem(item) },
                                onTap: { handleItemTap(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func handleItemTap(_ item: ServerItem) {
        let folderTypes: [ItemType] = [.folder, .collectionFolder, .userView]
        if folderTypes.contains(item.type) {
            Task { await viewModel.navigateToFolder(id: item.id, name: item.name) }
        } else if item.isFolder == true {
            router.navigate(to: .libraryBrowser(itemId: item.id, serverId: item.serverId))
        } else {
            router.navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId))
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

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))
            Text(message)
                .font(.bodyLg)
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FolderItemCard: View {
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

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    cardImage
                    cardOverlays
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))

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
        .buttonStyle(FolderCardButtonStyle(isFocused: isFocused))
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
        case .photo, .photoAlbum: return "photo"
        case .folder, .collectionFolder, .userView: return "folder.fill"
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

            if item.isFolder == true {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

private struct FolderCardButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .opacity(isFocused ? 1.0 : 0.75)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
