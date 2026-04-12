import SwiftUI
import Nuke

private enum DetailsRestoreTarget: Equatable {
    case button(ActionButtonID)
    case track(String)
    case content(String)
}

struct ItemDetailsView: View {
    @StateObject private var viewModel: ItemDetailViewModel
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @FocusState private var focusedButton: ActionButtonID?
    @FocusState private var focusedTrackId: String?
    @FocusState private var focusedEpisodeId: String?
    @State private var showFullBio = false
    @State private var showTrackSelector: TrackSelectorMode?
    @State private var showAddToPlaylist = false
    @State private var showDeleteConfirmation = false
    @State private var showSubtitleDownload = false
    @State private var playlistDialogItemIds: [String] = []
    @State private var selectedAudioIndex: Int?
    @State private var selectedSubtitleIndex: Int?
    @State private var selectedMediaSourceIndex: Int = 0
    let sidebarEntryToken: Int
    let sidebarHandoffToken: Int
    @State private var currentFocusTarget: DetailsRestoreTarget?
    @State private var sidebarEntryFocusTarget: DetailsRestoreTarget?
    @State private var restoredContentId: String?
    @State private var restoreContentFocusTrigger: Int = 0
    @State private var restoredEpisodeId: String?
    @State private var restoreEpisodeFocusTrigger: Int = 0
    private let routeServerId: String?
    private let autoPlay: Bool
    @State private var didAutoPlay = false

    private func focusTrace(_ message: String) {
        _ = message
    }

    private func describe(_ target: DetailsRestoreTarget?) -> String {
        guard let target else { return "nil" }
        switch target {
        case .button(let button):
            return "button:\(String(describing: button))"
        case .track(let id):
            return "track:\(id)"
        case .content(let id):
            return "content:\(id)"
        }
    }

    private func restoreDetailsFocus(_ target: DetailsRestoreTarget) {
        focusTrace("restoring target=\(describe(target))")
        switch target {
        case .button(let button):
            focusedButton = nil
            DispatchQueue.main.async {
                focusedButton = button
            }
        case .track(let id):
            focusedTrackId = nil
            DispatchQueue.main.async {
                focusedTrackId = id
            }
        case .content(let id):
            restoredContentId = id
            restoreContentFocusTrigger += 1
            restoredEpisodeId = id
            restoreEpisodeFocusTrigger += 1
        }
    }

    private var navbarIsLeft: Bool {
        container.userPreferences[UserPreferences.navbarPosition] == .left
    }

    private var contentLeading: CGFloat {
        navbarIsLeft ? LeftSidebar.sidebarInset : 50
    }

    init(
        container: AppContainer,
        itemId: String,
        serverId: String? = nil,
        autoPlay: Bool = false,
        sidebarEntryToken: Int = 0,
        sidebarHandoffToken: Int = 0
    ) {
        _viewModel = StateObject(wrappedValue: ItemDetailViewModel(
            container: container,
            itemId: itemId,
            serverId: serverId
        ))
        self.routeServerId = serverId
        self.autoPlay = autoPlay
        self.sidebarEntryToken = sidebarEntryToken
        self.sidebarHandoffToken = sidebarHandoffToken
    }

    var body: some View {
        configuredScreen
        .overlay { addToPlaylistOverlay }
        .sheet(isPresented: $showSubtitleDownload) {
            subtitleDownloadOverlay
        }
        .confirmationDialog(
            "Delete Item?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    let deleted = await deleteCurrentItem()
                    if deleted {
                        router.goBack()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This item will be permanently deleted from the server.")
        }
    }

    private var configuredScreen: AnyView {
        AnyView(
            baseScreen
        .ignoresSafeArea()
        .onAppear {
            focusTrace("ItemDetailsView appeared itemId=\(viewModel.item?.id ?? "loading")")
            viewModel.loadItem()
        }
        .onDisappear { viewModel.cleanup() }
        .onChange(of: viewModel.isLoading) { isLoading in
            if !isLoading, viewModel.item != nil {
                DispatchQueue.main.async {
                    focusedButton = viewModel.canResume ? .resume : .play
                    focusTrace("initial focusedButton=\(String(describing: focusedButton))")
                }
                initializeTrackIndices()

                if autoPlay, !didAutoPlay, let item = viewModel.item {
                    didAutoPlay = true
                    let ticks = item.userData?.playbackPositionTicks ?? 0
                    playVideo(item: item, positionTicks: ticks)
                }
            }
        }
        .onChange(of: focusedButton) { newValue in
            focusTrace("focusedButton changed to \(String(describing: newValue))")
            if let newValue {
                currentFocusTarget = .button(newValue)
            }
        }
        .onChange(of: focusedTrackId) { newValue in
            focusTrace("focusedTrackId changed to \(newValue ?? "nil")")
            if let newValue {
                currentFocusTarget = .track(newValue)
            }
        }
        .onChange(of: focusedEpisodeId) { newValue in
            focusTrace("focusedEpisodeId changed to \(newValue ?? "nil")")
            if let newValue {
                currentFocusTarget = .content(newValue)
            }
        }
        .onChange(of: sidebarEntryToken) { _ in
            guard navbarIsLeft else { return }
            sidebarEntryFocusTarget = currentFocusTarget
            focusTrace("captured sidebar entry target=\(describe(sidebarEntryFocusTarget))")
        }
        .onChange(of: sidebarHandoffToken) { _ in
            guard navbarIsLeft else { return }
            let restoreTarget = sidebarEntryFocusTarget ?? currentFocusTarget
            focusTrace("sidebar handoff target=\(describe(restoreTarget))")
            guard let restoreTarget else { return }
            restoreDetailsFocus(restoreTarget)
        }
        .sheet(item: $showTrackSelector) { mode in
            if let item = viewModel.item {
                if mode == .version {
                    VersionSelectorDialog(
                        sources: item.mediaSources ?? [],
                        selectedIndex: selectedMediaSourceIndex,
                        onSelect: { index in
                            selectedMediaSourceIndex = index
                            selectedAudioIndex = nil
                            selectedSubtitleIndex = nil
                            initializeTrackIndices()
                            showTrackSelector = nil
                        },
                        onDismiss: { showTrackSelector = nil }
                    )
                } else {
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
                        onDismiss: { showTrackSelector = nil },
                        onDownloadSubtitles: mode == .subtitle && subtitleClient()?.serverType == .jellyfin ? {
                            showTrackSelector = nil
                            showSubtitleDownload = true
                        } : nil
                    )
                }
            }
        }
        )
    }

    private var baseScreen: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                backdropLayer
                gradientOverlay

                if viewModel.isLoading {
                    loadingView
                } else if let item = viewModel.item {
                    detailContent(item: item, screenHeight: geo.size.height)
                } else {
                    errorView
                }
            }
        }
    }

    @ViewBuilder
    private var addToPlaylistOverlay: some View {
        if showAddToPlaylist {
            ZStack {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()

                AddToPlaylistDialog(
                    itemIds: playlistDialogItemIds,
                    onDismiss: {
                        showAddToPlaylist = false
                        playlistDialogItemIds = []
                    },
                    onAdded: {
                        showAddToPlaylist = false
                        playlistDialogItemIds = []
                    }
                )
            }
            .focusSection()
        }
    }

    private var subtitleDownloadOverlay: some View {
        SubtitleDownloadDialog(
            defaultLanguage: subtitleSearchLanguage(for: _viewModel.wrappedValue.item),
            onSearch: searchRemoteSubtitles,
            onDownload: downloadRemoteSubtitle,
            onDismiss: { showSubtitleDownload = false },
            onDownloaded: { showSubtitleDownload = false }
        )
    }

    private func searchRemoteSubtitles(language: String) async throws -> [RemoteSubtitleResult] {
        guard let item = _viewModel.wrappedValue.item,
              let client = subtitleClient() else { throw URLError(.cancelled) }
        return try await client.userLibraryApi.searchRemoteSubtitles(itemId: item.id, language: language)
    }

    private func downloadRemoteSubtitle(subtitleId: String) async throws {
        guard let item = _viewModel.wrappedValue.item,
              let client = subtitleClient() else { throw URLError(.cancelled) }
        try await client.userLibraryApi.downloadRemoteSubtitle(itemId: item.id, subtitleId: subtitleId)
        _viewModel.wrappedValue.loadItem()
    }

    private func subtitleClient() -> MediaServerClient? {
        if let routeServerId,
           let parsedId = UUID.from(rawId: routeServerId),
           let server = container.serverRepository.storedServers.value.first(where: { $0.id == parsedId }) {
            return container.serverClientFactory.client(for: server)
        }

        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    private func deleteCurrentItem() async -> Bool {
        guard let item = _viewModel.wrappedValue.item,
              (item.canDelete ?? false),
              let client = subtitleClient() else {
            return false
        }

        do {
            try await client.userLibraryApi.deleteItem(itemId: item.id)
            return true
        } catch {
            return false
        }
    }

    private func initializeTrackIndices() {
        guard let sources = viewModel.item?.mediaSources,
              selectedMediaSourceIndex < sources.count else { return }
        let source = sources[selectedMediaSourceIndex]
        if selectedAudioIndex == nil {
            selectedAudioIndex = source.defaultAudioStreamIndex
        }
        if selectedSubtitleIndex == nil {
            selectedSubtitleIndex = source.defaultSubtitleStreamIndex
        }
    }

    private func resolvedStreams(for item: ServerItem) -> [ServerMediaStream] {
        if let sources = item.mediaSources, selectedMediaSourceIndex < sources.count {
            return sources[selectedMediaSourceIndex].mediaStreams
        }
        return item.mediaStreams ?? item.mediaSources?.first?.mediaStreams ?? []
    }

    private func subtitleSearchLanguage(for item: ServerItem?) -> String {
        let streams = item?.mediaSources?.first?.mediaStreams ?? []
        if let lang = streams.first(where: { $0.type == .subtitle })?.language, !lang.isEmpty { return lang }
        if let lang = streams.first(where: { $0.type == .audio })?.language, !lang.isEmpty { return lang }
        return "eng"
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
                .opacity(0.8)
                .transition(.opacity)
                .id(urlString)
            }
        }
        .drawingGroup()
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
        if item.type == .playlist {
            return AnyView(playlistHeaderSection(item: item))
        }

        if item.type == .musicAlbum {
            return AnyView(albumHeaderSection(item: item))
        }

        return AnyView(
        VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
            Spacer()

            HStack(alignment: .top, spacing: SpaceTokens.spaceXl) {
                if item.type == .person, let posterUrl = viewModel.posterUrl(for: item),
                   let url = URL(string: posterUrl) {
                    CachedImage(url: url, contentMode: .fit)
                        .frame(maxWidth: 280, maxHeight: 420)
                        .cornerRadius(RadiusTokens.medium)
                        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
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
                        CachedImage(url: url, contentMode: .fit)
                            .frame(maxHeight: 100)
                    } else {
                        Text(item.name)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(theme.colorScheme.onBackground)
                            .lineLimit(2)
                    }

                    if item.type != .person {
                        detailInfoRow(item: item)

                        if !viewModel.ratings.isEmpty {
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
                                .font(.bodyMd)
                                .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, SpaceTokens.spaceXs)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.type != .person {
                    let isEpisode = item.type == .episode
                    let isMusic = [ItemType.musicAlbum, .musicArtist, .playlist].contains(item.type)
                    let imageUrlString: String? = isEpisode
                        ? viewModel.imageUrl(for: item, imageType: .thumb)
                        : viewModel.posterUrl(for: item)

                    if let imageUrlString, let url = URL(string: imageUrlString) {
                        if isEpisode {
                            CachedImage(url: url, contentMode: .fill)
                                .frame(maxWidth: 320, maxHeight: 180)
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .clipped()
                                .cornerRadius(RadiusTokens.medium)
                                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                        } else {
                            CachedImage(url: url, contentMode: .fit)
                                .frame(maxWidth: 240, maxHeight: isMusic ? 240 : 360)
                                .cornerRadius(RadiusTokens.medium)
                                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                        }
                    }
                }
            }
            .padding(.top, 80)
            .padding(.bottom, SpaceTokens.spaceXl)
        }
        )
    }

    private func albumHeaderSection(item: ServerItem) -> some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Spacer(minLength: 40)

            if let imageUrlString = viewModel.posterUrl(for: item),
               let url = URL(string: imageUrlString) {
                CachedImage(url: url, contentMode: .fit)
                    .frame(width: 280, height: 280)
                    .cornerRadius(RadiusTokens.medium)
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
            }

            VStack(spacing: SpaceTokens.spaceSm) {
                if let logoUrl = viewModel.logoUrl(for: item),
                   let url = URL(string: logoUrl) {
                    CachedImage(url: url, contentMode: .fit)
                        .frame(maxHeight: 90)
                } else {
                    Text(item.name)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(theme.colorScheme.onBackground)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack {
                    Spacer()
                    detailInfoRow(item: item)
                    Spacer()
                }

                if !viewModel.ratings.isEmpty {
                    HStack {
                        Spacer()
                        ratingsRow
                        Spacer()
                    }
                }

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)
                        .padding(.top, SpaceTokens.spaceXs)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, SpaceTokens.spaceMd)
    }

    private func playlistHeaderSection(item: ServerItem) -> some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Spacer(minLength: 40)

            if let imageUrlString = viewModel.posterUrl(for: item),
               let url = URL(string: imageUrlString) {
                CachedImage(url: url, contentMode: .fit)
                    .frame(width: 260, height: 260)
                    .cornerRadius(RadiusTokens.medium)
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
            }

            VStack(spacing: SpaceTokens.spaceSm) {
                if let logoUrl = viewModel.logoUrl(for: item),
                   let url = URL(string: logoUrl) {
                    CachedImage(url: url, contentMode: .fit)
                        .frame(maxHeight: 90)
                } else {
                    Text(item.name)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(theme.colorScheme.onBackground)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack {
                    Spacer()
                    detailInfoRow(item: item)
                    Spacer()
                }
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, SpaceTokens.spaceMd)
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

            if item.type == .series, let seasonCount = item.childCount, seasonCount > 0 {
                infoText(seasonCount == 1 ? "1 Season" : "\(seasonCount) Seasons")
                infoSeparator
            }

            if item.type == .series, let status = item.status?.lowercased(),
               status == "continuing" || status == "ended" {
                seriesStatusBadge(status)
                if item.officialRating != nil || !viewModel.badges.isEmpty {
                    infoSeparator
                }
            }

            if let rating = item.officialRating, !rating.isEmpty {
                infoBadge(rating)
                if !viewModel.badges.isEmpty {
                    infoSeparator
                }
            }

            ForEach(viewModel.badges) { badge in
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

    private func seriesStatusBadge(_ status: String) -> some View {
        let isContinuing = status == "continuing"
        let label = isContinuing ? "Continuing" : "Ended"
        let badgeColor = isContinuing ? Color.green : Color.red
        return Text(label)
            .font(.bodySm)
            .foregroundColor(.white)
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.8), in: RoundedRectangle(cornerRadius: RadiusTokens.extraSmall))
    }

    private var ratingsRow: some View {
        let showLabels = viewModel.showRatingLabels
        return HStack(spacing: SpaceTokens.spaceSm) {
            ForEach(viewModel.ratings, id: \.0) { source, value in
                if source == "stars" {
                    starRatingChip(value: value, showLabel: showLabels)
                } else {
                    RatingChipView(source: source, normalizedValue: value, showLabel: showLabels)
                }
            }
        }
    }

    private func starRatingChip(value: Float, showLabel: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 24))
                .foregroundColor(Color(red: 1, green: 0.84, blue: 0))
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                if showLabel {
                    Text("Community rating")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
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
            case .musicArtist, .albumArtist:
                artistSections()
            case .boxSet:
                collectionSections()
            case .movie, .trailer, .video:
                movieSections()
            default:
                defaultSections()
            }
        }
    }

    @ViewBuilder
    private func actionButtonsSection(item: ServerItem) -> some View {
        let isMusicType = [ItemType.musicAlbum, .musicArtist, .playlist].contains(item.type)
        let isPlayableMusicCollection = [ItemType.musicAlbum, .playlist].contains(item.type)
        let isReadableBook = item.type == .book || item.mediaType == .book
        let canPlay = isMusicType || isReadableBook || [ItemType.movie, .episode, .video, .series, .season].contains(item.type)
        let showGoToSeries = item.type == .episode && item.seriesId != nil
        let canDelete = item.canDelete ?? false
        let hasMultipleVersions = (item.mediaSources?.count ?? 0) > 1
        let hasTrailers = item.type == .movie
            || item.type == .series
            || (item.localTrailerCount ?? 0) > 0
            || !(item.remoteTrailers ?? []).isEmpty
        let streams = resolvedStreams(for: item)
        let hasAudioStreams = streams.contains { $0.type == .audio }
        let hasSubtitleStreams = streams.contains { $0.type == .subtitle }
        let isJellyfin = subtitleClient()?.serverType == .jellyfin
        let canDownloadSubtitles = isJellyfin
            && !hasSubtitleStreams
            && !(item.mediaSources ?? []).isEmpty
            && item.type != .photo
            && item.type != .book
            && item.type != .musicArtist

        if item.type != .person, canPlay || item.userData != nil {
            ActionButtonsRow(
                isFavorite: viewModel.isFavorite,
                isPlayed: viewModel.isPlayed,
                canResume: viewModel.canResume,
                resumePositionText: viewModel.resumePositionText,
                focusedButton: $focusedButton,
                onPlay: {
                    if isPlayableMusicCollection {
                        playAudio(items: viewModel.tracks)
                    } else if isReadableBook {
                        router.navigate(to: .bookReader(itemId: item.id, serverId: item.effectiveServerId))
                    } else {
                        playVideo(item: item, positionTicks: 0)
                    }
                },
                onResume: {
                    if isPlayableMusicCollection {
                        playAudio(items: viewModel.tracks)
                    } else if isReadableBook {
                        router.navigate(to: .bookReader(itemId: item.id, serverId: item.effectiveServerId))
                    } else {
                        let ticks = item.userData?.playbackPositionTicks ?? 0
                        playVideo(item: item, positionTicks: ticks)
                    }
                },
                onToggleWatched: { viewModel.toggleWatched() },
                onToggleFavorite: { viewModel.toggleFavorite() },
                onShuffle: isMusicType ? {
                    playAudio(items: viewModel.tracks, shuffle: true)
                } : nil,
                onInstantMix: isMusicType ? {
                    Task {
                        await viewModel.loadInstantMix()
                        playAudio(items: viewModel.instantMixItems)
                    }
                } : nil,
                onNextEpisode: nil,
                onSelectVersion: hasMultipleVersions ? {
                    showTrackSelector = .version
                } : nil,
                onAudioTrack: hasAudioStreams ? {
                    showTrackSelector = .audio
                } : nil,
                onSubtitleTrack: hasSubtitleStreams ? {
                    showTrackSelector = .subtitle
                } : nil,
                onDownloadSubtitles: canDownloadSubtitles ? {
                    showSubtitleDownload = true
                } : nil,
                onTrailer: hasTrailers ? {
                    Task { await playTrailer(item: item) }
                } : nil,
                onGoToSeries: showGoToSeries ? {
                    if let seriesId = item.seriesId {
                        router.navigate(to: .itemDetails(itemId: seriesId))
                    }
                } : nil,
                onAddToPlaylist: canPlay ? {
                    playlistDialogItemIds = [item.id]
                    showAddToPlaylist = true
                } : nil,
                onDelete: canDelete ? {
                    showDeleteConfirmation = true
                } : nil
            )
        }
    }

    private func playVideo(item: ServerItem, positionTicks: Int64) {
        let items: [ServerItem]
        var startIndex = 0
        var startPosition = TimeInterval(positionTicks) / 10_000_000

        switch item.type {
        case .episode:
            let episodes = viewModel.episodes
            if episodes.isEmpty {
                items = [item]
            } else {
                items = episodes
                startIndex = episodes.firstIndex(where: { $0.id == item.id }) ?? 0
            }
        case .series:
            if let nextUpEpisode = viewModel.nextUp.first {
                items = [nextUpEpisode]
                if positionTicks > 0 {
                    startPosition = TimeInterval(nextUpEpisode.userData?.playbackPositionTicks ?? 0) / 10_000_000
                } else {
                    startPosition = 0
                }
            } else {
                return
            }
        case .season:
            let episodes = viewModel.episodes
            guard !episodes.isEmpty else { return }
            items = episodes
            if positionTicks == 0,
               let firstUnwatched = episodes.firstIndex(where: { !($0.userData?.played ?? false) }) {
                startIndex = firstUnwatched
                startPosition = TimeInterval(episodes[firstUnwatched].userData?.playbackPositionTicks ?? 0) / 10_000_000
            }
        default:
            items = [item]
        }

        Task {
            await container.playbackCoordinator.startVideoPlayback(
                items: items,
                startIndex: startIndex,
                startPosition: startPosition,
                serverId: routeServerId ?? item.effectiveServerId,
                audioStreamIndex: selectedAudioIndex,
                subtitleStreamIndex: selectedSubtitleIndex,
                mediaSourceIndex: selectedMediaSourceIndex > 0 ? selectedMediaSourceIndex : nil
            )
            router.navigate(to: .videoPlayer)
        }
    }

    private func playAudio(items: [ServerItem], startIndex: Int = 0, shuffle: Bool = false) {
        guard !items.isEmpty else { return }
        Task {
            await container.playbackCoordinator.startAudioPlayback(
                items: items,
                startIndex: startIndex,
                serverId: routeServerId,
                shuffle: shuffle
            )
            router.navigate(to: .nowPlaying)
        }
    }

    private func playTrailer(item: ServerItem) async {
        let server: Server?
        if let routeServerId,
           let parsedId = UUID.from(rawId: routeServerId) {
            server = container.serverRepository.storedServers.value.first(where: { $0.id == parsedId })
        } else {
            server = container.serverRepository.currentServer.value
        }

        guard let server else { return }
        let client = container.serverClientFactory.client(for: server)
        _ = await TrailerPlaybackHelper.playTrailer(
            for: item,
            client: client,
            playbackCoordinator: container.playbackCoordinator,
            router: router
        )
    }

    private func playTrackNext(_ track: ServerItem) {
        if let audio = container.playbackCoordinator.audioManager, audio.hasQueue {
            let newEntry = QueueEntry(
                id: track.id,
                item: track,
                mediaSourceId: track.mediaSources?.first?.id,
                startPositionTicks: 0
            )
            var queue = audio.queue
            let insertionIndex = min(max(audio.currentIndex + 1, 0), queue.count)
            queue.insert(newEntry, at: insertionIndex)
            audio.playbackManager.replaceQueue(queue)
            return
        }

        playAudio(items: [track])
    }

    private func addTrackToQueue(_ track: ServerItem) {
        if let audio = container.playbackCoordinator.audioManager {
            audio.addToQueue(items: [track])
            return
        }

        playAudio(items: [track])
    }

    private func toggleTrackFavorite(_ track: ServerItem) {
        let isFavorite = track.userData?.isFavorite ?? false
        Task {
            _ = try? await container.itemMutationService.setFavorite(itemId: track.id, isFavorite: !isFavorite)
            viewModel.loadItem()
        }
    }

    private func metadataColumns(for item: ServerItem) -> [(label: String, value: String)] {
        var columns: [(label: String, value: String)] = []
        let genres = item.genres ?? []
        let directors = viewModel.directors
        let writers = viewModel.writers
        let studios = item.studios ?? []

        if item.type != .playlist, !genres.isEmpty {
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
        if !viewModel.nextUp.isEmpty {
            detailSection(title: "Next Up", id: "nextUp") {
                episodeList(items: viewModel.nextUp)
            }
        }
        if !viewModel.seasons.isEmpty {
            detailSection(title: "Seasons", id: "seasons") {
                seasonRow
            }
        }
        castSection
        similarSection
    }

    @ViewBuilder
    private func seasonSections() -> some View {
        if !viewModel.episodes.isEmpty {
            detailSection(title: "Episodes", id: "episodes") {
                episodeList(items: viewModel.episodes)
            }
        }
        castSection
        similarSection
    }

    @ViewBuilder
    private func episodeSections() -> some View {
        chaptersSection
        if let nextEp = viewModel.nextEpisode {
            detailSection(title: "Next Episode", id: "nextEp") {
                episodeList(items: [nextEp])
            }
        }
        if viewModel.episodes.count > 1 {
            let others = viewModel.episodes.filter { $0.id != viewModel.item?.id }
            if !others.isEmpty {
                detailSection(title: "More from This Season", id: "moreEpisodes") {
                    itemRow(items: others, imageType: .thumb, aspectRatio: 16.0/9.0, cardWidth: 280)
                }
            }
        }
        castSection
        specialFeaturesSection
        similarSection
    }

    @ViewBuilder
    private func personSections() -> some View {
        if let item = viewModel.item {
            personInfoSection(item: item)
        }
        let movies = viewModel.filmography.filter { $0.type == .movie }
        let series = viewModel.filmography.filter { $0.type == .series }
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
        if !viewModel.tracks.isEmpty {
            detailSection(title: "Tracks", id: "tracks") {
                interactiveTrackList(items: viewModel.tracks)
            }
        }
        similarSection
    }

    @ViewBuilder
    private func artistSections() -> some View {
        if let item = viewModel.item, let bio = item.overview, !bio.isEmpty {
            detailSection(title: "Biography", id: "artistBio") {
                ExpandableBioText(
                    text: bio,
                    isExpanded: $showFullBio
                )
            }
        }
        if !viewModel.albums.isEmpty {
            detailSection(title: "Discography", id: "albums") {
                itemRow(items: viewModel.albums, aspectRatio: 1.0)
            }
        }
        similarSection
    }

    @ViewBuilder
    private func collectionSections() -> some View {
        let movies = viewModel.collectionItems.filter { $0.type == .movie }
        let series = viewModel.collectionItems.filter { $0.type == .series }
        let other = viewModel.collectionItems.filter { $0.type != .movie && $0.type != .series }

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
        chaptersSection
        specialFeaturesSection
        parentCollectionSection
        similarSection
    }

    @ViewBuilder
    private func defaultSections() -> some View {
        castSection
        similarSection
    }

    @ViewBuilder
    private var castSection: some View {
        if !viewModel.cast.isEmpty {
            detailSection(title: "Cast & Crew", id: "cast") {
                castRow
            }
        }
    }

    @ViewBuilder
    private var similarSection: some View {
        if !viewModel.similar.isEmpty {
            detailSection(title: "More Like This", id: "similar") {
                itemRow(items: viewModel.similar)
            }
        }
    }

    @ViewBuilder
    private var specialFeaturesSection: some View {
        if !viewModel.specialFeatures.isEmpty {
            detailSection(title: "Special Features", id: "specials") {
                itemRow(items: viewModel.specialFeatures, imageType: .primary, aspectRatio: 16.0/9.0)
            }
        }
    }

    @ViewBuilder
    private var parentCollectionSection: some View {
        if !viewModel.parentCollectionItems.isEmpty {
            detailSection(title: viewModel.parentCollectionName ?? "Collection", id: "parentCollection") {
                itemRow(items: viewModel.parentCollectionItems)
            }
        }
    }

    @ViewBuilder
    private var chaptersSection: some View {
        if let item = viewModel.item,
           let chapters = item.chapters,
           !chapters.isEmpty {
            detailSection(title: "Chapters", id: "chapters") {
                chapterRow(item: item, chapters: chapters)
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

        return FocusFirstRow(
            firstItemId: items.first?.id,
            restoredItemId: restoredContentId,
            focusTrigger: restoreContentFocusTrigger
        ) { focusBinding in
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(items) { item in
                    FocusableItemCard(
                        item: item,
                        imageUrl: viewModel.imageUrl(for: item, imageType: imageType, maxWidth: Int(cardWidth * 2)),
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        onSelect: {
                            router.navigateToItem(item)
                        },
                        onFocused: {
                            focusTrace("focused itemRow sectionItem=\(item.id)")
                            currentFocusTarget = .content(item.id)
                        }
                    )
                    .focused(focusBinding, equals: item.id)
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceSm)
        }
    }

    private func chapterRow(item: ServerItem, chapters: [ServerChapter]) -> some View {
        let cardWidth: CGFloat = 240
        let cardHeight: CGFloat = 135

        return FocusFirstRow(
            firstItemId: chapters.first.map(chapterFocusId),
            restoredItemId: restoredContentId,
            focusTrigger: restoreContentFocusTrigger
        ) { focusBinding in
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(chapters) { chapter in
                    let isFocused = focusBinding.wrappedValue == chapterFocusId(chapter)
                    Button {
                        playVideo(item: item, positionTicks: chapter.startPositionTicks)
                    } label: {
                        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                            ZStack {
                                if let imageUrl = viewModel.chapterImageUrl(for: chapter) {
                                    CachedImage(urlString: imageUrl)
                                        .frame(width: cardWidth, height: cardHeight)
                                        .clipped()
                                } else {
                                    Rectangle()
                                        .fill(theme.colorScheme.surface)
                                        .frame(width: cardWidth, height: cardHeight)
                                        .overlay(
                                            Image(systemName: "film")
                                                .font(.titleXl)
                                                .foregroundColor(theme.colorScheme.listCaption)
                                        )
                                }
                            }
                            .cornerRadius(RadiusTokens.small)
                            .overlay(
                                RoundedRectangle(cornerRadius: RadiusTokens.small)
                                    .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
                            )

                            Text(chapter.name ?? "Chapter")
                                .font(.bodySm)
                                .foregroundColor(theme.colorScheme.onBackground)
                                .lineLimit(1)
                                .frame(width: cardWidth, alignment: .leading)

                            Text(RuntimeFormatter.format(ticks: chapter.startPositionTicks))
                                .font(.caption2xs)
                                .foregroundColor(theme.colorScheme.listCaption)
                        }
                    }
                    .buttonStyle(PopupCardButtonStyle())
                    .focused(focusBinding, equals: chapterFocusId(chapter))
                    .onChange(of: focusBinding.wrappedValue) { focusedId in
                        if focusedId == chapterFocusId(chapter) {
                            currentFocusTarget = .content(chapterFocusId(chapter))
                        }
                    }
                }
            }
            .padding(.horizontal, SpaceTokens.spaceLg)
            .padding(.vertical, SpaceTokens.spaceSm)
        }
    }

    private func chapterFocusId(_ chapter: ServerChapter) -> String {
        return "chapter:\(chapter.startPositionTicks)"
    }

    private var castRow: some View {
        FocusFirstRow(
            firstItemId: viewModel.cast.first.map { $0.id ?? $0.name },
            restoredItemId: restoredContentId,
            focusTrigger: restoreContentFocusTrigger
        ) { focusBinding in
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(viewModel.cast, id: \.name) { person in
                    let focusId = person.id ?? person.name
                    FocusableCastCard(
                        person: person,
                        imageUrl: viewModel.imageUrl(for: person),
                        onSelect: {
                            if let id = person.id {
                                router.navigate(to: .itemDetails(itemId: id))
                            }
                        },
                        onFocused: {
                            focusTrace("focused castRow person=\(focusId)")
                            currentFocusTarget = .content(focusId)
                        }
                    )
                    .focused(focusBinding, equals: focusId)
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceSm)
        }
    }

    private var seasonRow: some View {
        FocusFirstRow(
            firstItemId: viewModel.seasons.first?.id,
            restoredItemId: restoredContentId,
            focusTrigger: restoreContentFocusTrigger
        ) { focusBinding in
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(viewModel.seasons) { season in
                    FocusableSeasonCard(
                        item: season,
                        imageUrl: viewModel.imageUrl(for: season, maxWidth: 320),
                        onSelect: {
                            router.navigate(to: .itemDetails(itemId: season.id, serverId: season.serverId))
                        },
                        onFocused: {
                            focusTrace("focused seasonRow season=\(season.id)")
                            currentFocusTarget = .content(season.id)
                        }
                    )
                    .focused(focusBinding, equals: season.id)
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceSm)
        }
    }

    private func episodeList(items: [ServerItem]) -> some View {
        LazyVStack(spacing: SpaceTokens.spaceSm) {
            ForEach(items) { episode in
                FocusableEpisodeCard(
                    item: episode,
                    imageUrl: viewModel.imageUrl(for: episode, imageType: .thumb, maxWidth: 560),
                    onSelect: {
                        router.navigate(to: .itemDetails(itemId: episode.id, serverId: episode.serverId))
                    },
                    onFocused: {
                        focusTrace("focused episodeList episode=\(episode.id)")
                        currentFocusTarget = .content(episode.id)
                    }
                )
                .focused($focusedEpisodeId, equals: episode.id)
            }
        }
        .defaultFocus($focusedEpisodeId, restoredEpisodeId ?? items.first?.id, priority: .userInitiated)
        .onChange(of: restoreEpisodeFocusTrigger) { _ in
            guard let target = restoredEpisodeId else { return }
            focusedEpisodeId = nil
            DispatchQueue.main.async {
                focusedEpisodeId = target
            }
        }
    }

    private func interactiveTrackList(items: [ServerItem]) -> some View {
        let canManagePlaylist = viewModel.canManagePlaylistTracks

        return LazyVStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let track = items[index]
                let canMoveUp = canManagePlaylist && index > 0
                let canMoveDown = canManagePlaylist && index < items.count - 1

                let onRemoveFromPlaylist: (() -> Void)? = canManagePlaylist ? {
                    Task { await viewModel.removeTrackFromPlaylist(track) }
                } : nil

                let onMoveUp: (() -> Void)? = canMoveUp ? {
                    Task {
                        await viewModel.movePlaylistItem(fromIndex: index, toIndex: index - 1)
                        focusedTrackId = track.id
                    }
                } : nil

                let onMoveDown: (() -> Void)? = canMoveDown ? {
                    Task {
                        await viewModel.movePlaylistItem(fromIndex: index, toIndex: index + 1)
                        focusedTrackId = track.id
                    }
                } : nil

                FocusableTrackRow(
                    track: track,
                    rowIndex: index,
                    focusBinding: $focusedTrackId,
                    focusId: track.id,
                    onSelect: { playAudio(items: items, startIndex: index) },
                    onPlayNext: { playTrackNext(track) },
                    onAddToQueue: { addTrackToQueue(track) },
                    onAddToPlaylist: {
                        playlistDialogItemIds = [track.id]
                        showAddToPlaylist = true
                    },
                    onRemoveFromPlaylist: onRemoveFromPlaylist,
                    onMoveUp: onMoveUp,
                    onMoveDown: onMoveDown,
                    onToggleFavorite: { toggleTrackFavorite(track) },
                    onGoToAlbum: track.albumId != nil ? {
                        if let albumId = track.albumId {
                            router.navigate(to: .itemDetails(itemId: albumId, serverId: track.serverId))
                        }
                    } : nil,
                    onGoToArtist: (track.albumArtists?.first?.id) != nil ? {
                        if let artistId = track.albumArtists?.first?.id {
                            router.navigate(to: .itemDetails(itemId: artistId, serverId: track.serverId))
                        }
                    } : nil,
                    onMoveLeft: onMoveUp,
                    onMoveRight: onMoveDown,
                    onFocused: {
                        focusedTrackId = track.id
                        focusTrace("focused track=\(track.id)")
                    }
                )
            }
        }
        .defaultFocus($focusedTrackId, items.first?.id, priority: .userInitiated)
    }
}
