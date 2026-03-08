import SwiftUI

struct ItemDetailsView: View {
    @StateObject private var viewModel: ItemDetailViewModel
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    private var navbarIsLeft: Bool {
        container.userPreferences[UserPreferences.navbarPosition] == .left
    }

    private var contentLeading: CGFloat {
        navbarIsLeft ? LeftSidebar.sidebarInset : 50
    }

    init(container: AppContainer, itemId: String, serverId: String? = nil) {
        _viewModel = StateObject(wrappedValue: ItemDetailViewModel(
            container: container,
            itemId: itemId,
            serverId: serverId
        ))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                backdropLayer
                gradientOverlay

                if viewModel.state.isLoading {
                    loadingView
                } else if let item = viewModel.state.item {
                    detailContent(item: item, screenHeight: geo.size.height)
                } else {
                    errorView
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { viewModel.loadItem() }
        .onDisappear { viewModel.cleanup() }
    }

    private var backdropLayer: some View {
        GeometryReader { geo in
            if viewModel.backgroundService.enabled,
               let urlString = viewModel.backgroundService.currentBackdropUrl,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: viewModel.backgroundService.blurAmount)
                            .opacity(0.8)
                    }
                }
                .transition(.opacity)
                .id(urlString)
            }
        }
        .animation(.easeInOut(duration: BackgroundService.transitionDuration), value: viewModel.backgroundService.currentBackdropUrl)
        .background(theme.colorScheme.background)
    }

    private var gradientOverlay: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: theme.colorScheme.background.opacity(0.9), location: 0),
                    .init(color: theme.colorScheme.background.opacity(0.5), location: 0.3),
                    .init(color: theme.colorScheme.background.opacity(0.3), location: 0.6),
                    .init(color: theme.colorScheme.background.opacity(0.8), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: theme.colorScheme.background.opacity(0.5), location: 0.5),
                    .init(color: theme.colorScheme.background.opacity(0.95), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .tint(theme.colorScheme.onBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Text("Unable to load item")
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground)
            Button("Go Back") { router.goBack() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailContent(item: ServerItem, screenHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerSection(item: item)
                    .frame(minHeight: screenHeight * 0.52)

                contentSections(item: item)
                    .padding(.top, SpaceTokens.spaceLg)
            }
            .padding(.leading, contentLeading)
            .padding(.trailing, 50)
        }
    }

    private func headerSection(item: ServerItem) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
            Spacer()

            HStack(alignment: .top, spacing: SpaceTokens.spaceXl) {
                if let posterUrl = viewModel.posterUrl(for: item),
                   let url = URL(string: posterUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 240, maxHeight: 360)
                                .cornerRadius(RadiusTokens.medium)
                                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                    if let logoUrl = viewModel.logoUrl(for: item),
                       let url = URL(string: logoUrl) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 100)
                            }
                        }
                    } else {
                        Text(item.name)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(theme.colorScheme.onBackground)
                            .lineLimit(2)
                    }

                    SimpleInfoRow(item: item)

                    if !viewModel.state.badges.isEmpty {
                        badgeRow
                    }

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.bodyLg)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                            .lineLimit(5)
                            .padding(.top, SpaceTokens.spaceSm)
                    }
                }
            }
            .padding(.top, 80)
            .padding(.bottom, SpaceTokens.spaceXl)
        }
    }

    private var badgeRow: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            ForEach(viewModel.state.badges) { badge in
                Text(badge.label)
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBadge)
                    .padding(.horizontal, SpaceTokens.spaceSm)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                            .fill(theme.colorScheme.badge)
                    )
            }
        }
    }

    @ViewBuilder
    private func contentSections(item: ServerItem) -> some View {
        LazyVStack(alignment: .leading, spacing: SpaceTokens.spaceXl) {
            switch item.type {
            case .series:
                seriesSections()
            case .season:
                seasonSections()
            case .episode:
                episodeSections()
            case .person:
                personSections()
            case .musicAlbum, .playlist:
                musicSections()
            case .musicArtist:
                artistSections()
            case .boxSet:
                collectionSections()
            default:
                defaultSections()
            }
        }
    }

    @ViewBuilder
    private func seriesSections() -> some View {
        if !viewModel.state.nextUp.isEmpty {
            detailSection(title: "Next Up", id: "nextUp") {
                itemRow(items: viewModel.state.nextUp, imageType: .thumb, aspectRatio: 16.0/9.0)
            }
        }
        if !viewModel.state.seasons.isEmpty {
            detailSection(title: "Seasons", id: "seasons") {
                itemRow(items: viewModel.state.seasons)
            }
        }
        castSection
        similarSection
    }

    @ViewBuilder
    private func seasonSections() -> some View {
        if !viewModel.state.episodes.isEmpty {
            detailSection(title: "Episodes", id: "episodes") {
                itemRow(items: viewModel.state.episodes, imageType: .thumb, aspectRatio: 16.0/9.0)
            }
        }
    }

    @ViewBuilder
    private func episodeSections() -> some View {
        castSection
        similarSection
    }

    @ViewBuilder
    private func personSections() -> some View {
        if !viewModel.state.similar.isEmpty {
            detailSection(title: "Known For", id: "filmography") {
                itemRow(items: viewModel.state.similar)
            }
        }
    }

    @ViewBuilder
    private func musicSections() -> some View {
        if !viewModel.state.tracks.isEmpty {
            detailSection(title: "Tracks", id: "tracks") {
                trackList(items: viewModel.state.tracks)
            }
        }
    }

    @ViewBuilder
    private func artistSections() -> some View {
        if !viewModel.state.albums.isEmpty {
            detailSection(title: "Albums", id: "albums") {
                itemRow(items: viewModel.state.albums, aspectRatio: 1.0)
            }
        }
        similarSection
    }

    @ViewBuilder
    private func collectionSections() -> some View {
        if !viewModel.state.collectionItems.isEmpty {
            detailSection(title: "Items", id: "collection") {
                itemRow(items: viewModel.state.collectionItems)
            }
        }
    }

    @ViewBuilder
    private func defaultSections() -> some View {
        castSection
        similarSection
    }

    @ViewBuilder
    private var castSection: some View {
        if !viewModel.state.cast.isEmpty {
            detailSection(title: "Cast & Crew", id: "cast") {
                castRow
            }
        }
    }

    @ViewBuilder
    private var similarSection: some View {
        if !viewModel.state.similar.isEmpty {
            detailSection(title: "More Like This", id: "similar") {
                itemRow(items: viewModel.state.similar)
            }
        }
    }

    private func detailSection<Content: View>(
        title: String,
        id: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(title)
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.listHeader)
                .padding(.leading, SpaceTokens.spaceSm)

            content()
        }
        .id(id)
        .focusSection()
    }

    private func itemRow(
        items: [ServerItem],
        imageType: ImageType = .primary,
        aspectRatio: CGFloat = 2.0/3.0
    ) -> some View {
        let cardWidth: CGFloat = aspectRatio >= 1.0 ? 200 : 160
        let cardHeight = cardWidth / aspectRatio

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(items) { item in
                    Button {
                        router.navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId))
                    } label: {
                        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                            if let urlStr = viewModel.imageUrl(for: item, imageType: imageType, maxWidth: Int(cardWidth * 2)),
                               let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        theme.colorScheme.surface
                                    }
                                }
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                                .cornerRadius(RadiusTokens.small)
                            } else {
                                theme.colorScheme.surface
                                    .frame(width: cardWidth, height: cardHeight)
                                    .cornerRadius(RadiusTokens.small)
                            }

                            Text(item.name)
                                .font(.bodySm)
                                .foregroundColor(theme.colorScheme.onBackground)
                                .lineLimit(1)
                                .frame(width: cardWidth, alignment: .leading)
                        }
                    }
                    .buttonStyle(CleanButtonStyle())
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
        }
    }

    private var castRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(viewModel.state.cast, id: \.name) { person in
                    Button {
                        if let id = person.id {
                            router.navigate(to: .itemDetails(itemId: id))
                        }
                    } label: {
                        VStack(spacing: SpaceTokens.spaceXs) {
                            if let urlStr = viewModel.imageUrl(for: person),
                               let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        theme.colorScheme.surface
                                    }
                                }
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(theme.colorScheme.surface)
                                    .frame(width: 120, height: 120)
                            }

                            Text(person.name)
                                .font(.bodySm)
                                .foregroundColor(theme.colorScheme.onBackground)
                                .lineLimit(1)

                            if let role = person.role, !role.isEmpty {
                                Text(role)
                                    .font(.caption2xs)
                                    .foregroundColor(theme.colorScheme.listCaption)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 130)
                    }
                    .buttonStyle(CleanButtonStyle())
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
        }
    }

    private func trackList(items: [ServerItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { track in
                HStack {
                    if let num = track.indexNumber {
                        Text("\(num)")
                            .font(.bodyMd)
                            .foregroundColor(theme.colorScheme.listCaption)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Text(track.name)
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.onBackground)
                    Spacer()
                    if let ticks = track.runTimeTicks {
                        Text(RuntimeFormatter.format(ticks: ticks))
                            .font(.bodySm)
                            .foregroundColor(theme.colorScheme.listCaption)
                    }
                }
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.vertical, SpaceTokens.spaceSm)

                Divider()
                    .background(theme.colorScheme.onBackground.opacity(0.1))
            }
        }
    }
}
