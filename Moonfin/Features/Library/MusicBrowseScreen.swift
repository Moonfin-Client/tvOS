import SwiftUI
import Nuke

struct MusicBrowseScreen: View {
    @StateObject private var viewModel: MusicBrowseViewModel
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
                    action: { router.navigate(to: .home) }
                )
            }

            musicNavButtons
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

    private var musicNavButtons: some View {
        HStack(spacing: 8) {
            MusicNavButton(title: "Albums", theme: theme) {
                router.navigate(to: .libraryBrowserByType(
                    itemId: viewModel.parentId, includeType: ItemType.musicAlbum.rawValue
                ))
            }

            MusicNavButton(title: "Artists", theme: theme) {
                router.navigate(to: .libraryBrowserByType(
                    itemId: viewModel.parentId, includeType: ItemType.musicArtist.rawValue
                ))
            }

            MusicNavButton(title: "Genres", theme: theme) {
                router.navigate(to: .libraryByGenres(
                    itemId: viewModel.parentId, includeType: ItemType.musicAlbum.rawValue
                ))
            }
        }
    }

    // MARK: - Content

    private var musicContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(row.items) { item in
                        MusicSquareCard(
                            item: item,
                            imageUrl: viewModel.squareImageUrl(for: item),
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

    // MARK: - Navigation

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
    let onFocused: () -> Void
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

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
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused() }
        }
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

// MARK: - Music Nav Button

private struct MusicNavButton: View {
    let title: String
    let theme: MoonfinTheme
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bodySm)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isFocused ? theme.focusBorder.color : Color.white.opacity(0.1))
                )
                .foregroundColor(isFocused ? .white : .white.opacity(0.7))
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
