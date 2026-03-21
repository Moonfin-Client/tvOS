import SwiftUI
import Nuke

struct SeerrDiscoverView: View {
    @StateObject private var viewModel: SeerrDiscoverViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var container: AppContainer

    private var navbarIsLeft: Bool {
        container.userPreferences[UserPreferences.navbarPosition] == .left
    }

    private var contentLeading: CGFloat {
        navbarIsLeft ? LeftSidebar.sidebarInset : 50
    }

    init(seerrRepository: SeerrRepositoryProtocol) {
        _viewModel = StateObject(wrappedValue: SeerrDiscoverViewModel(seerrRepository: seerrRepository))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                backdropLayer(size: geo.size)
                gradientOverlay
                infoArea
                    .allowsHitTesting(false)
                    .zIndex(1)
                rowsContent(screenHeight: geo.size.height)
                    .zIndex(0)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            router.resetNavbarVisibility()
            viewModel.loadContent()
            viewModel.refreshRequests()
        }
    }

    private func backdropLayer(size: CGSize) -> some View {
        Group {
            if let urlString = viewModel.currentBackdropUrl, let url = URL(string: urlString) {
                CachedImage(
                    url: url,
                    processors: [
                        ImageProcessors.Resize(size: size, contentMode: .aspectFill),
                        ImageProcessors.GaussianBlur(radius: 8)
                    ]
                )
                .frame(width: size.width, height: size.height)
                .clipped()
                .drawingGroup()
                .transition(.opacity)
                .id(urlString)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: viewModel.currentBackdropUrl)
        .background(theme.colorScheme.background)
    }

    private var gradientOverlay: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: theme.colorScheme.background.opacity(0.85), location: 0),
                    .init(color: theme.colorScheme.background.opacity(0.4), location: 0.4),
                    .init(color: theme.colorScheme.background.opacity(0.3), location: 0.6),
                    .init(color: theme.colorScheme.background.opacity(0.7), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: theme.colorScheme.background.opacity(0.6), location: 0.7),
                    .init(color: theme.colorScheme.background.opacity(0.95), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            if !viewModel.selectedItem.title.isEmpty {
                Text(viewModel.selectedItem.title)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
            }

            if !viewModel.selectedItem.year.isEmpty || !viewModel.selectedItem.mediaType.isEmpty || viewModel.selectedItem.voteAverage > 0 {
                HStack(spacing: SpaceTokens.spaceMd) {
                    if !viewModel.selectedItem.mediaType.isEmpty {
                        Text(viewModel.selectedItem.mediaType)
                            .font(.titleMd)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                    }
                    if !viewModel.selectedItem.year.isEmpty {
                        Text(viewModel.selectedItem.year)
                            .font(.titleMd)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                    }
                    if viewModel.selectedItem.voteAverage > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.titleSm)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", viewModel.selectedItem.voteAverage))
                                .font(.titleMd)
                                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                        }
                    }
                }
            }

            if !viewModel.selectedItem.overview.isEmpty {
                Text(viewModel.selectedItem.overview)
                    .font(.titleXl)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(3)
            }
        }
        .padding(.leading, contentLeading)
        .padding(.trailing, 50)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedItem.title)
    }

    private func rowsContent(screenHeight: CGFloat) -> some View {
        let rowsTop = screenHeight * 0.38
        return VStack(spacing: 0) {
            Spacer().frame(height: rowsTop)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
                    let visibleRows = viewModel.rows.filter { !$0.isEmpty }
                    ForEach(visibleRows) { row in
                        SeerrDiscoverRowView(
                            row: row,
                            viewModel: viewModel,
                            onItemSelected: { item in
                                if let json = viewModel.itemJson(item) {
                                    router.navigate(to: .seerrMediaDetails(itemJson: json))
                                }
                            },
                            onGenreSelected: { genre, mediaType in
                                router.navigate(to: .seerrBrowseBy(
                                    filterId: genre.id,
                                    filterName: genre.name,
                                    mediaType: mediaType
                                ))
                            },
                            onStudioSelected: { studio in
                                router.navigate(to: .seerrBrowseBy(
                                    filterId: studio.id,
                                    filterName: studio.name,
                                    mediaType: "movie",
                                    filterType: "studio"
                                ))
                            },
                            onNetworkSelected: { network in
                                router.navigate(to: .seerrBrowseBy(
                                    filterId: network.id,
                                    filterName: network.name,
                                    mediaType: "tv",
                                    filterType: "network"
                                ))
                            }
                        )
                        .id(row.id)
                    }
                }
                .padding(.leading, contentLeading)
                .padding(.trailing, 50)
            }
            .focusSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
