import SwiftUI

struct ItemDetailsView: View {
    @StateObject private var viewModel: ItemDetailViewModel
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @FocusState private var focusedButton: ActionButtonID?
    @State private var showFullBio = false
    @State private var showTrackSelector: TrackSelectorMode?
    @State private var showAddToPlaylist = false
    @State private var selectedAudioIndex: Int?
    @State private var selectedSubtitleIndex: Int?

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
        .onChange(of: viewModel.state.isLoading) { isLoading in
            if !isLoading, viewModel.state.item != nil {
                DispatchQueue.main.async {
                    focusedButton = viewModel.canResume ? .resume : .play
                }
                initializeTrackIndices()
            }
        }
        .sheet(item: $showTrackSelector) { mode in
            if let item = viewModel.state.item {
                TrackSelectorDialog(
                    mode: mode,
                    streams: resolvedStreams(for: item),
                    selectedIndex: mode == .audio ? selectedAudioIndex : selectedSubtitleIndex,
                    onSelect: { index in
                        if mode == .audio {
                            selectedAudioIndex = index
                        } else {
                            selectedSubtitleIndex = index
                        }
                        showTrackSelector = nil
                    },
                    onDismiss: { showTrackSelector = nil }
                )
            }
        }
        .fullScreenCover(isPresented: $showAddToPlaylist) {
            if let item = viewModel.state.item {
                AddToPlaylistDialog(
                    itemIds: [item.id],
                    onDismiss: { showAddToPlaylist = false },
                    onAdded: { showAddToPlaylist = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.8))
            }
        }
    }

    private func initializeTrackIndices() {
        guard let source = viewModel.state.item?.mediaSources?.first else { return }
        if selectedAudioIndex == nil {
            selectedAudioIndex = source.defaultAudioStreamIndex
        }
        if selectedSubtitleIndex == nil {
            selectedSubtitleIndex = source.defaultSubtitleStreamIndex
        }
    }

    private func resolvedStreams(for item: ServerItem) -> [ServerMediaStream] {
        item.mediaStreams ?? item.mediaSources?.first?.mediaStreams ?? []
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

                actionButtonsSection(item: item)
                    .padding(.top, SpaceTokens.spaceXl)
                    .padding(.leading, -contentLeading)
                    .padding(.trailing, -50)

                metadataSection(item: item)
                    .padding(.top, SpaceTokens.spaceMd)

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
                if item.type == .person, let posterUrl = viewModel.posterUrl(for: item),
                   let url = URL(string: posterUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 280, maxHeight: 420)
                                .cornerRadius(RadiusTokens.medium)
                                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                    if (item.type == .episode || item.type == .season),
                       let seriesName = item.seriesName {
                        Text(seriesName)
                            .font(.title2xl)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    }

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

                    if item.type != .person {
                        detailInfoRow(item: item)

                        if let genres = item.genres, !genres.isEmpty {
                            Text(genres.joined(separator: ", "))
                                .font(.bodyMd)
                                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                        }

                        if !viewModel.state.ratings.isEmpty {
                            ratingsRow
                        }

                        if let tagline = item.taglines?.first, !tagline.isEmpty {
                            Text("\"\(tagline)\"")
                                .font(.bodyMd)
                                .italic()
                                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                        }

                        if let overview = item.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.titleXl)
                                .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                                .lineLimit(5)
                                .padding(.top, SpaceTokens.spaceXs)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.type != .person, let posterUrl = viewModel.posterUrl(for: item),
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
            }
            .padding(.top, 80)
            .padding(.bottom, SpaceTokens.spaceXl)
        }
    }

    private func detailInfoRow(item: ServerItem) -> some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            if item.type == .episode,
               let season = item.parentIndexNumber,
               let episode = item.indexNumber {
                infoText("S\(season):E\(episode)")
                infoSeparator
            }

            if let year = item.productionYear, year > 0 {
                infoText(String(year))
                infoSeparator
            }

            if let ticks = item.runTimeTicks, ticks > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                    infoText(RuntimeFormatter.format(ticks: ticks))
                }
                infoSeparator
            }

            if let endsAt = viewModel.endsAtText {
                infoText(endsAt)
                infoSeparator
            }

            if let rating = item.officialRating, !rating.isEmpty {
                infoBadge(rating)
                if !viewModel.state.badges.isEmpty {
                    infoSeparator
                }
            }

            ForEach(viewModel.state.badges) { badge in
                infoBadge(badge.label)
            }
        }
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .font(.bodyMd)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
    }

    private var infoSeparator: some View {
        Text("·")
            .font(.bodyMd)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
    }

    private func infoBadge(_ text: String) -> some View {
        Text(text)
            .font(.bodySm)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                    .stroke(theme.colorScheme.onBackground.opacity(0.3), lineWidth: 1)
            )
    }

    private var ratingsRow: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            ForEach(viewModel.state.ratings, id: \.0) { source, value in
                if source == "stars" {
                    starRatingChip(value: value)
                } else {
                    RatingChipView(source: source, normalizedValue: value, showLabel: true)
                }
            }
        }
    }

    private func starRatingChip(value: Float) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 18))
                .foregroundColor(Color(red: 1, green: 0.84, blue: 0))
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("Community rating")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.1))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func contentSections(item: ServerItem) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXl) {
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
            case .movie, .video:
                movieSections()
            default:
                defaultSections()
            }
        }
    }

    @ViewBuilder
    private func actionButtonsSection(item: ServerItem) -> some View {
        let isMusicType = [ItemType.musicAlbum, .musicArtist, .playlist].contains(item.type)
        let canPlay = isMusicType || [ItemType.movie, .episode, .video, .series, .season].contains(item.type)
        let showGoToSeries = item.type == .episode && item.seriesId != nil
        let hasNextEpisode = item.type == .episode && viewModel.nextEpisode != nil
        let streams = resolvedStreams(for: item)
        let hasAudioStreams = streams.contains { $0.type == .audio }
        let hasSubtitleStreams = streams.contains { $0.type == .subtitle }

        if item.type != .person, canPlay || item.userData != nil {
            ActionButtonsRow(
                isFavorite: viewModel.state.isFavorite,
                isPlayed: viewModel.state.isPlayed,
                canResume: viewModel.canResume,
                resumePositionText: viewModel.resumePositionText,
                focusedButton: $focusedButton,
                onPlay: { router.navigate(to: .videoPlayer(position: 0)) },
                onResume: {
                    let pos = Int(item.userData?.playbackPositionTicks ?? 0)
                    router.navigate(to: .videoPlayer(position: pos))
                },
                onToggleWatched: { viewModel.toggleWatched() },
                onToggleFavorite: { viewModel.toggleFavorite() },
                onGoToSeries: showGoToSeries ? {
                    if let seriesId = item.seriesId {
                        router.navigate(to: .itemDetails(itemId: seriesId))
                    }
                } : nil,
                onNextEpisode: hasNextEpisode ? {
                    if let nextEp = viewModel.nextEpisode {
                        router.navigate(to: .itemDetails(itemId: nextEp.id, serverId: nextEp.serverId))
                    }
                } : nil,
                onShuffle: isMusicType ? {
                    router.navigate(to: .videoPlayer(position: 0))
                } : nil,
                onInstantMix: isMusicType ? {
                    Task {
                        await viewModel.loadInstantMix()
                        router.navigate(to: .videoPlayer(position: 0))
                    }
                } : nil,
                onAudioTrack: hasAudioStreams ? {
                    showTrackSelector = .audio
                } : nil,
                onSubtitleTrack: hasSubtitleStreams ? {
                    showTrackSelector = .subtitle
                } : nil,
                onAddToPlaylist: canPlay ? {
                    showAddToPlaylist = true
                } : nil
            )
        }
    }

    private func metadataColumns(for item: ServerItem) -> [(label: String, value: String)] {
        var columns: [(label: String, value: String)] = []
        let genres = item.genres ?? []
        let directors = viewModel.state.directors
        let writers = viewModel.state.writers
        let studios = item.studios ?? []

        if !genres.isEmpty {
            columns.append(("Genres", genres.joined(separator: ", ")))
        }
        if !directors.isEmpty {
            columns.append((directors.count > 1 ? "Directors" : "Director",
                            directors.map(\.name).joined(separator: ", ")))
        }
        if !writers.isEmpty {
            columns.append((writers.count > 1 ? "Writers" : "Writer",
                            writers.map(\.name).joined(separator: ", ")))
        }
        if !studios.isEmpty {
            columns.append((studios.count > 1 ? "Studios" : "Studio",
                            studios.compactMap(\.name).joined(separator: ", ")))
        }
        return columns
    }

    @ViewBuilder
    private func metadataSection(item: ServerItem) -> some View {
        let columns = metadataColumns(for: item)

        if !columns.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1, height: 36)
                    }

                    VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                        Text(column.label.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
                            .tracking(0.5)
                        Text(column.value)
                            .font(.bodySm)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.85))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SpaceTokens.spaceLg)
                }
            }
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func seriesSections() -> some View {
        if !viewModel.state.nextUp.isEmpty {
            detailSection(title: "Next Up", id: "nextUp") {
                episodeList(items: viewModel.state.nextUp)
            }
        }
        if !viewModel.state.seasons.isEmpty {
            detailSection(title: "Seasons", id: "seasons") {
                seasonRow
            }
        }
        castSection
        similarSection
    }

    @ViewBuilder
    private func seasonSections() -> some View {
        if !viewModel.state.episodes.isEmpty {
            detailSection(title: "Episodes", id: "episodes") {
                episodeList(items: viewModel.state.episodes)
            }
        }
        castSection
        similarSection
    }

    @ViewBuilder
    private func episodeSections() -> some View {
        if let nextEp = viewModel.nextEpisode {
            detailSection(title: "Next Episode", id: "nextEp") {
                episodeList(items: [nextEp])
            }
        }
        if viewModel.state.episodes.count > 1 {
            let others = viewModel.state.episodes.filter { $0.id != viewModel.state.item?.id }
            if !others.isEmpty {
                detailSection(title: "More from This Season", id: "moreEpisodes") {
                    itemRow(items: others, imageType: .thumb, aspectRatio: 16.0/9.0, cardWidth: 280)
                }
            }
        }
        castSection
        similarSection
    }

    @ViewBuilder
    private func personSections() -> some View {
        if let item = viewModel.state.item {
            personInfoSection(item: item)
        }
        let movies = viewModel.state.filmography.filter { $0.type == .movie }
        let series = viewModel.state.filmography.filter { $0.type == .series }
        if !movies.isEmpty {
            detailSection(title: "Movies", id: "movies") {
                itemRow(items: movies)
            }
        }
        if !series.isEmpty {
            detailSection(title: "Series", id: "series") {
                itemRow(items: series)
            }
        }
    }

    @ViewBuilder
    private func personInfoSection(item: ServerItem) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
            personDateRow(item: item)

            if let overview = item.overview, !overview.isEmpty {
                detailSection(title: "Biography", id: "biography") {
                    ExpandableBioText(
                        text: overview,
                        isExpanded: $showFullBio
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func personDateRow(item: ServerItem) -> some View {
        let parts = personDateParts(item: item)
        if !parts.isEmpty {
            HStack(spacing: SpaceTokens.spaceSm) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 { infoSeparator }
                    infoText(part)
                }
            }
        }
    }

    private static let dateDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func personDateParts(item: ServerItem) -> [String] {
        var parts: [String] = []
        let formatter = Self.dateDisplayFormatter

        if let birthDate = item.premiereDate {
            parts.append("Born \(formatter.string(from: birthDate))")
            if let deathDate = item.endDate {
                parts.append("Died \(formatter.string(from: deathDate))")
            }
            if let age = Self.calculateAge(from: birthDate, to: item.endDate) {
                parts.append("Age \(age)")
            }
        }

        if let locations = item.productionLocations, let birthplace = locations.first {
            parts.append(birthplace)
        }

        return parts
    }

    private static func calculateAge(from birthDate: Date, to endDate: Date?) -> Int? {
        Calendar.current.dateComponents([.year], from: birthDate, to: endDate ?? Date()).year
    }

    @ViewBuilder
    private func musicSections() -> some View {
        if !viewModel.state.tracks.isEmpty {
            detailSection(title: "Tracks", id: "tracks") {
                interactiveTrackList(items: viewModel.state.tracks)
            }
        }
        similarSection
    }

    @ViewBuilder
    private func artistSections() -> some View {
        if let item = viewModel.state.item, let bio = item.overview, !bio.isEmpty {
            detailSection(title: "Biography", id: "artistBio") {
                ExpandableBioText(
                    text: bio,
                    isExpanded: $showFullBio
                )
            }
        }
        if !viewModel.state.albums.isEmpty {
            detailSection(title: "Discography", id: "albums") {
                itemRow(items: viewModel.state.albums, aspectRatio: 1.0)
            }
        }
        similarSection
    }

    @ViewBuilder
    private func collectionSections() -> some View {
        let movies = viewModel.state.collectionItems.filter { $0.type == .movie }
        let series = viewModel.state.collectionItems.filter { $0.type == .series }
        let other = viewModel.state.collectionItems.filter { $0.type != .movie && $0.type != .series }

        if !movies.isEmpty {
            detailSection(title: "Movies", id: "collectionMovies") {
                itemRow(items: movies)
            }
        }
        if !series.isEmpty {
            detailSection(title: "Series", id: "collectionSeries") {
                itemRow(items: series)
            }
        }
        if !other.isEmpty {
            detailSection(title: "Other", id: "collectionOther") {
                itemRow(items: other)
            }
        }
    }

    @ViewBuilder
    private func movieSections() -> some View {
        castSection
        specialFeaturesSection
        similarSection
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

    @ViewBuilder
    private var specialFeaturesSection: some View {
        if !viewModel.state.specialFeatures.isEmpty {
            detailSection(title: "Special Features", id: "specials") {
                itemRow(items: viewModel.state.specialFeatures, imageType: .primary, aspectRatio: 16.0/9.0)
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
                .padding(.bottom, SpaceTokens.spaceXs)

            content()
        }
        .id(id)
        .focusSection()
    }

    private func itemRow(
        items: [ServerItem],
        imageType: ImageType = .primary,
        aspectRatio: CGFloat = 2.0/3.0,
        cardWidth overrideWidth: CGFloat? = nil
    ) -> some View {
        let cardWidth: CGFloat = overrideWidth ?? (aspectRatio >= 1.0 ? 200 : 160)
        let cardHeight = cardWidth / aspectRatio

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(items) { item in
                    FocusableItemCard(
                        item: item,
                        imageUrl: viewModel.imageUrl(for: item, imageType: imageType, maxWidth: Int(cardWidth * 2)),
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        onSelect: {
                            router.navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId))
                        }
                    )
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceSm)
        }
    }

    private var castRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(viewModel.state.cast, id: \.name) { person in
                    FocusableCastCard(
                        person: person,
                        imageUrl: viewModel.imageUrl(for: person),
                        onSelect: {
                            if let id = person.id {
                                router.navigate(to: .itemDetails(itemId: id))
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceSm)
        }
    }

    private var seasonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(viewModel.state.seasons) { season in
                    FocusableSeasonCard(
                        item: season,
                        imageUrl: viewModel.imageUrl(for: season, maxWidth: 320),
                        onSelect: {
                            router.navigate(to: .itemDetails(itemId: season.id, serverId: season.serverId))
                        }
                    )
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceSm)
        }
    }

    private func episodeList(items: [ServerItem]) -> some View {
        VStack(spacing: SpaceTokens.spaceSm) {
            ForEach(items) { episode in
                FocusableEpisodeCard(
                    item: episode,
                    imageUrl: viewModel.imageUrl(for: episode, imageType: .thumb, maxWidth: 560),
                    onSelect: {
                        router.navigate(to: .itemDetails(itemId: episode.id, serverId: episode.serverId))
                    }
                )
            }
        }
    }

    private func interactiveTrackList(items: [ServerItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { track in
                FocusableTrackRow(
                    track: track,
                    onSelect: {
                        router.navigate(to: .videoPlayer(position: 0))
                    }
                )
            }
        }
    }
}

private struct FocusableItemCard: View {
    let item: ServerItem
    let imageUrl: String?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                ZStack {
                    if let urlStr = imageUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                theme.colorScheme.surface
                            }
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                    } else {
                        theme.colorScheme.surface
                            .frame(width: cardWidth, height: cardHeight)
                    }

                    ItemCardOverlays(item: item)
                }
                .cornerRadius(RadiusTokens.small)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
                )

                Text(item.name)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

private struct FocusableCastCard: View {
    let person: ServerPerson
    let imageUrl: String?
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: SpaceTokens.spaceXs) {
                ZStack {
                    if let urlStr = imageUrl, let url = URL(string: urlStr) {
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
                }
                .overlay(
                    Circle()
                        .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
                )

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
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

private struct FocusableSeasonCard: View {
    let item: ServerItem
    let imageUrl: String?
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth / (2.0 / 3.0) }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                ZStack {
                    if let urlStr = imageUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                theme.colorScheme.surface
                            }
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                    } else {
                        theme.colorScheme.surface
                            .frame(width: cardWidth, height: cardHeight)
                    }

                    ItemCardOverlays(item: item)
                }
                .cornerRadius(RadiusTokens.small)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
                )

                Text(item.name)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

private struct FocusableEpisodeCard: View {
    let item: ServerItem
    let imageUrl: String?
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let thumbWidth: CGFloat = 280
    private let thumbHeight: CGFloat = 158

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: SpaceTokens.spaceMd) {
                ZStack {
                    if let urlStr = imageUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                theme.colorScheme.surface
                            }
                        }
                        .frame(width: thumbWidth, height: thumbHeight)
                        .clipped()
                    } else {
                        theme.colorScheme.surface
                            .frame(width: thumbWidth, height: thumbHeight)
                    }

                    if let progress = item.userData?.playedPercentage, progress > 0,
                       !(item.userData?.played ?? false) {
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

                    if item.userData?.played ?? false {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.colorGreen500)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(6)
                    }
                }
                .cornerRadius(RadiusTokens.small)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
                )

                VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                    if let num = item.indexNumber {
                        Text("Episode \(num)")
                            .font(.captionXs)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
                    }

                    Text(item.name)
                        .font(.bodyLg)
                        .fontWeight(.semibold)
                        .foregroundColor(theme.colorScheme.onBackground)
                        .lineLimit(1)

                    if let ticks = item.runTimeTicks, ticks > 0 {
                        Text(RuntimeFormatter.format(ticks: ticks))
                            .font(.captionXs)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
                    }

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.bodySm)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, SpaceTokens.spaceXs)
            }
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

private struct ExpandableBioText: View {
    let text: String
    @Binding var isExpanded: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                Text(text)
                    .font(.bodyLg)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(isExpanded ? nil : 6)
                    .padding(.horizontal, SpaceTokens.spaceSm)

                if !isExpanded {
                    Text("Press to expand")
                        .font(.captionXs)
                        .foregroundColor(isFocused ? .white.opacity(0.7) : theme.colorScheme.onBackground.opacity(0.4))
                        .padding(.horizontal, SpaceTokens.spaceSm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}

private struct FocusableTrackRow: View {
    let track: ServerItem
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SpaceTokens.spaceSm) {
                if let num = track.indexNumber {
                    Text("\(num)")
                        .font(.bodyMd)
                        .foregroundColor(isFocused ? .white : theme.colorScheme.listCaption)
                        .frame(width: 40, alignment: .trailing)
                }
                Text(track.name)
                    .font(.bodyMd)
                    .foregroundColor(isFocused ? .white : theme.colorScheme.onBackground)
                    .lineLimit(1)
                Spacer()
                if let ticks = track.runTimeTicks {
                    Text(RuntimeFormatter.format(ticks: ticks))
                        .font(.bodySm)
                        .foregroundColor(isFocused ? .white.opacity(0.7) : theme.colorScheme.listCaption)
                }
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? theme.accent : Color.clear)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}
