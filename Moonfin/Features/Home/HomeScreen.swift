import SwiftUI
import Nuke

struct HomeScreen: View {
    private static let infoLogoReservedHeight: CGFloat = 128
    private static let infoLogoMaxWidth: CGFloat = 560
    private static let infoMetaReservedHeight: CGFloat = 28
    private static let infoRatingsReservedHeight: CGFloat = 40
    private static let infoSummaryReservedHeight: CGFloat = 120
    private static let infoAreaTotalHeight: CGFloat =
        infoLogoReservedHeight + infoMetaReservedHeight + infoRatingsReservedHeight + infoSummaryReservedHeight + (3 * SpaceTokens.spaceSm)

    @StateObject private var viewModel: HomeViewModel
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var previewManager: PreviewPlayerManager
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    let mainNamespace: Namespace.ID
    @Binding var contentReady: Bool
    @Binding var suppressTopNavbarInRows: Bool
    let sidebarEntryToken: Int
    let sidebarHandoffToken: Int
    let onRequestTopNavbarHomeFocus: (() -> Void)?
    @State private var isMediaBarMode = true
    @State private var sentinelEnabled = false
    @State private var focusedRowId: String?
    @State private var scrollTrigger: Int = 0
    @State private var lastFocusedRowId: String?
    @State private var lastFocusedItemId: String?
    @State private var navigatedFromMediaBar = false
    @State private var isRestoringPosition = false
    @State private var mediaBarRequestFocus = false
    @State private var focusTask: Task<Void, Never>?
    @State private var sentinelTask: Task<Void, Never>?
    @State private var mediaBarTrailerPreviewTask: Task<Void, Never>?
    @State private var lastPreviewedMediaBarItemId: String?
    @StateObject private var inlineTrailerPlayer: VLCPlayerWrapper
    @Environment(\.resetFocus) private var resetFocus
    @State private var focusFirstRowTrigger: Int = 0
    @State private var restoreRowFocusTrigger: Int = 0
    @State private var restoreScrollTrigger: Int = 0
    @Namespace private var rowsNamespace
    @State private var suppressTopNavbarUntilMediaBarFocus = false
    @State private var lastContentAreaWasMediaBar = false
    @State private var sidebarEntryRowId: String?
    @State private var sidebarEntryItemId: String?
    @State private var sidebarEntryWasMediaBar = false
    @State private var hasInitiallyFocusedFirstRow = false

    private var navbarIsLeft: Bool {
        container.userPreferences[UserPreferences.navbarPosition] == .left
    }

    private var contentLeading: CGFloat {
        navbarIsLeft ? LeftSidebar.sidebarInset : 50
    }

    private var rowsShouldPreferDefaultFocus: Bool {
        suppressTopNavbarInRows
    }

    private var seasonalSurprise: SeasonalSurprise {
        container.userPreferences[UserPreferences.seasonalSurprise]
    }

    init(
        container: AppContainer,
        mainNamespace: Namespace.ID,
        contentReady: Binding<Bool> = .constant(true),
        sidebarEntryToken: Int = 0,
        sidebarHandoffToken: Int = 0,
        suppressTopNavbarInRows: Binding<Bool> = .constant(false),
        onRequestTopNavbarHomeFocus: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(container: container))
        _inlineTrailerPlayer = StateObject(wrappedValue: MpvPlayerWrapper.makePreferredPlayer())
        self.mainNamespace = mainNamespace
        self._contentReady = contentReady
        self.sidebarEntryToken = sidebarEntryToken
        self.sidebarHandoffToken = sidebarHandoffToken
        self._suppressTopNavbarInRows = suppressTopNavbarInRows
        self.onRequestTopNavbarHomeFocus = onRequestTopNavbarHomeFocus
    }

    private func resolveFocus(delay: UInt64 = 50_000_000) {
        focusTask?.cancel()
        focusTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            if isRestoringPosition, lastFocusedRowId != nil {
                restoreScrollTrigger += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                resetFocus(in: rowsNamespace)
                return
            }
            if isRestoringPosition {
                isRestoringPosition = false
                sentinelEnabled = viewModel.isMediaBarActive
            }
            if isMediaBarMode && viewModel.isMediaBarActive {
                mediaBarRequestFocus = true
            } else if navbarIsLeft {
                DispatchQueue.main.async {
                    focusFirstRowTrigger += 1
                }
            } else {
                resetFocus(in: mainNamespace)
            }
        }
    }

    private func scheduleSidebarRowRestore(delay: UInt64 = 100_000_000) {
        focusTask?.cancel()
        focusTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            restoreRowFocusTrigger += 1
        }
    }

    private func requestMediaBarFocus(after delay: Double = 0.05) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            mediaBarRequestFocus = true
            if suppressTopNavbarUntilMediaBarFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    suppressTopNavbarUntilMediaBarFocus = false
                    syncTopNavbarSuppression()
                }
            }
        }
    }

    private func syncTopNavbarSuppression() {
        guard viewModel.hasFocusableContent else {
            suppressTopNavbarInRows = false
            return
        }
        let mediaBarEnabled = viewModel.mediaBarViewModel.isEnabled
        suppressTopNavbarInRows = mediaBarEnabled && (!isMediaBarMode || suppressTopNavbarUntilMediaBarFocus)
    }

    var body: some View {
        GeometryReader { geo in
            let showMediaBar = viewModel.mediaBarViewModel.isEnabled && (viewModel.isMediaBarActive || viewModel.isMediaBarLoading)
            let mediaBarPresented = isMediaBarMode && showMediaBar

            ZStack(alignment: .topLeading) {
                if mediaBarPresented {
                    MediaBarView(
                        viewModel: viewModel.mediaBarViewModel,
                        ratingsViewModel: viewModel.mediaBarRatingsViewModel,
                        userPreferences: container.userPreferences,
                        screenHeight: geo.size.height,
                        inlineTrailerPlayer: inlineTrailerPlayer,
                        onItemSelected: { item in
                            cancelMediaBarTrailerPreview()
                            navigatedFromMediaBar = true
                            router.navigateToItem(item)
                        },
                        onPlayTrailer: { item in
                            cancelMediaBarTrailerPreview()
                            Task { await playTrailerFromMediaBar(item) }
                        },
                        onFocusedItemChanged: { item in
                            lastContentAreaWasMediaBar = item != nil
                            scheduleMediaBarTrailerPreview(for: item)
                        },
                        onNavigateDown: {
                            cancelMediaBarTrailerPreview()
                            sentinelEnabled = false
                            isMediaBarMode = false
                            let firstVisibleRowId = viewModel.rows.first(where: { !$0.isEmpty })?.id
                            lastFocusedRowId = firstVisibleRowId
                            focusedRowId = firstVisibleRowId
                            sentinelTask?.cancel()
                            sentinelTask = Task {
                                try? await Task.sleep(nanoseconds: 600_000_000)
                                guard !Task.isCancelled else { return }
                                sentinelEnabled = true
                            }
                            resolveFocus(delay: 150_000_000)
                            scheduleSidebarRowRestore(delay: 250_000_000)
                        },
                        onNavigateUp: {
                            onRequestTopNavbarHomeFocus?()
                        },
                        requestFocus: $mediaBarRequestFocus
                    )
                    .zIndex(1)
                }

                if !viewModel.isInitialLoad {
                    if !mediaBarPresented {
                        backdropLayer
                        gradientOverlay
                        infoArea
                            .allowsHitTesting(false)
                            .zIndex(1)
                    }
                    rowsContent(screenHeight: geo.size.height)
                        .disabled(mediaBarPresented)
                        .opacity(mediaBarPresented ? 0 : 1)
                        .focusSection()
                        .zIndex(0)

                }
            }
        }
        .ignoresSafeArea()
        .environmentObject(viewModel.backgroundService)
        .onAppear {
            viewModel.loadContent()
            suppressTopNavbarUntilMediaBarFocus = viewModel.mediaBarViewModel.isEnabled && lastFocusedRowId == nil
            syncTopNavbarSuppression()
            hasInitiallyFocusedFirstRow = false
            if navigatedFromMediaBar {
                isMediaBarMode = true
                navigatedFromMediaBar = false
                viewModel.mediaBarViewModel.resume()
            } else if lastFocusedRowId != nil {
                isMediaBarMode = false
                isRestoringPosition = true
                hasInitiallyFocusedFirstRow = true
                sentinelEnabled = false
                resolveFocus(delay: 100_000_000)
            } else if viewModel.isMediaBarActive {
                isMediaBarMode = true
                requestMediaBarFocus(after: 0)
            }
        }
        .onDisappear {
            focusTask?.cancel()
            sentinelTask?.cancel()
            cancelMediaBarTrailerPreview()
            viewModel.mediaBarViewModel.cleanup()
            suppressTopNavbarUntilMediaBarFocus = false
            suppressTopNavbarInRows = false
        }
        .onChange(of: viewModel.isMediaBarActive) { active in
            if active && lastFocusedRowId == nil {
                isMediaBarMode = true
                requestMediaBarFocus()
            }
        }
        .onChange(of: viewModel.isInitialLoad) { loading in
            guard !loading else { return }
            if !contentReady { contentReady = true }
            if !viewModel.hasFocusableContent {
                isMediaBarMode = false
                suppressTopNavbarUntilMediaBarFocus = false
                syncTopNavbarSuppression()
            }
        }
        .onChange(of: isMediaBarMode) { mode in
            syncTopNavbarSuppression()
            if mode { previewManager.stop() }
        }
        .onChange(of: container.inactivityTracker.isScreensaverVisible) { visible in
            if visible { previewManager.stop() }
        }
        .onChange(of: viewModel.hasFocusableContent) { ready in
            if ready {
                if !contentReady { contentReady = true }
                if !isRestoringPosition && !hasInitiallyFocusedFirstRow {
                    hasInitiallyFocusedFirstRow = true
                    if isMediaBarMode && viewModel.isMediaBarActive {
                        mediaBarRequestFocus = true
                    } else {
                        focusFirstRowTrigger += 1
                        scheduleSidebarRowRestore(delay: 100_000_000)
                    }
                }
            } else if !viewModel.isInitialLoad {
                if !contentReady { contentReady = true }
                suppressTopNavbarUntilMediaBarFocus = false
                syncTopNavbarSuppression()
            }
        }
        .onChange(of: sidebarHandoffToken) { _ in
            guard viewModel.hasFocusableContent else { return }
            let restoreMediaBar = sidebarEntryWasMediaBar || (viewModel.isMediaBarActive && lastContentAreaWasMediaBar)
            let restoreRowId = sidebarEntryRowId ?? lastFocusedRowId
            let restoreItemId = sidebarEntryItemId ?? lastFocusedItemId

            if viewModel.isMediaBarActive && restoreMediaBar {
                isMediaBarMode = true
                requestMediaBarFocus(after: 0)
                sidebarEntryWasMediaBar = false
                sidebarEntryRowId = nil
                sidebarEntryItemId = nil
                return
            }

            isMediaBarMode = false
            if !navbarIsLeft {
                focusFirstRowTrigger += 1
            } else {
                if let restoreRowId {
                    focusedRowId = restoreRowId
                    lastFocusedRowId = restoreRowId
                    lastFocusedItemId = restoreItemId
                    isRestoringPosition = true
                    hasInitiallyFocusedFirstRow = true
                    scrollTrigger += 1
                    scheduleSidebarRowRestore()
                } else {
                    resolveFocus(delay: 0)
                }
            }

            sidebarEntryWasMediaBar = false
            sidebarEntryRowId = nil
            sidebarEntryItemId = nil
        }
        .onChange(of: sidebarEntryToken) { _ in
            guard navbarIsLeft else { return }
            if isMediaBarMode && viewModel.isMediaBarActive {
                sidebarEntryWasMediaBar = true
                sidebarEntryRowId = nil
                sidebarEntryItemId = nil
                return
            }

            sidebarEntryWasMediaBar = false
            sidebarEntryRowId = focusedRowId ?? lastFocusedRowId
            if let rowId = sidebarEntryRowId, rowId == lastFocusedRowId {
                sidebarEntryItemId = lastFocusedItemId
            } else {
                sidebarEntryItemId = nil
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

            if seasonalSurprise != .none {
                seasonalTintOverlay
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var seasonalTintOverlay: some View {
        let tint: Color = {
            switch seasonalSurprise {
            case .none: return .clear
            case .winter: return Color.blue.opacity(0.12)
            case .spring: return Color.green.opacity(0.10)
            case .summer: return Color.orange.opacity(0.12)
            case .halloween: return Color.orange.opacity(0.18)
            case .fall: return Color(red: 0.64, green: 0.30, blue: 0.10).opacity(0.16)
            }
        }()

        LinearGradient(
            stops: [
                .init(color: tint, location: 0),
                .init(color: .clear, location: 0.55),
                .init(color: tint.opacity(0.7), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            ZStack(alignment: .leading) {
                if let logoUrl = viewModel.selectedItemState.logoUrl,
                   let url = URL(string: logoUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: Self.infoLogoMaxWidth, maxHeight: 120, alignment: .leading)
                        } else {
                            Color.clear
                        }
                    }
                } else if !viewModel.selectedItemState.title.isEmpty {
                    Text(viewModel.selectedItemState.title)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(theme.colorScheme.onBackground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(height: Self.infoLogoReservedHeight, alignment: .leading)

            SimpleInfoRow(item: viewModel.selectedItemState.item)
                .frame(height: Self.infoMetaReservedHeight, alignment: .leading)

            ZStack(alignment: .leading) {
                MediaBarRatingsRow(
                    ratings: viewModel.mediaBarRatingsViewModel.ratings,
                    enableAdditionalRatings: viewModel.mediaBarRatingsViewModel.enableAdditionalRatings
                )
            }
            .frame(height: Self.infoRatingsReservedHeight, alignment: .leading)
            .opacity(viewModel.mediaBarRatingsViewModel.ratings.isEmpty ? 0 : 1)

            ZStack(alignment: .topLeading) {
                Text(viewModel.selectedItemState.summary)
                    .font(.titleXl)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(4)
            }
            .frame(height: Self.infoSummaryReservedHeight, alignment: .topLeading)
            .opacity(viewModel.selectedItemState.summary.isEmpty ? 0 : 1)
        }
        .padding(.leading, contentLeading)
        .padding(.trailing, 50)
        .padding(.top, 80)
        .frame(height: Self.infoAreaTotalHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func rowsContent(screenHeight: CGFloat) -> some View {
        let rowsTop = screenHeight * 0.38

        return VStack(spacing: 0) {
            Spacer()
                .frame(height: rowsTop)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if viewModel.mediaBarViewModel.isEnabled && viewModel.isMediaBarActive && sentinelEnabled {
                            MediaBarReturnSentinel(
                                hasContent: viewModel.rows.contains(where: { !$0.isEmpty }),
                                onReturn: {
                                    isMediaBarMode = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        mediaBarRequestFocus = true
                                    }
                                }
                            )
                            .frame(height: 1)
                        }

                        VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
                            let visibleRows = viewModel.rows.filter { !$0.isEmpty }
                            ForEach(visibleRows) { row in
                                ContentRow(
                                    row: row,
                                    viewModel: viewModel,
                                    watchedIndicator: viewModel.watchedIndicator,
                                    titleTopPadding: visibleRows.first?.id == row.id ? 4 : 0,
                                    onRowFocused: {
                                        let isNewRow = focusedRowId != row.id
                                        focusedRowId = row.id
                                        if isRestoringPosition {
                                            if row.id == lastFocusedRowId {
                                                isRestoringPosition = false
                                                sentinelEnabled = viewModel.isMediaBarActive
                                            }
                                        } else if isNewRow {
                                            scrollTrigger += 1
                                        }
                                    },
                                    onItemFocused: { item in
                                        lastContentAreaWasMediaBar = false
                                        if !isRestoringPosition {
                                            focusedRowId = row.id
                                            lastFocusedRowId = row.id
                                            lastFocusedItemId = item.id
                                        }
                                    },
                                    onItemSelected: { item in
                                        navigatedFromMediaBar = false
                                        lastFocusedRowId = row.id
                                        lastFocusedItemId = item.id
                                        if row.rowType == .myMedia || row.rowType == .myMediaSmall {
                                            navigateToLibrary(item)
                                        } else if row.rowType == .liveTvButtons {
                                            navigateToLiveTvAction(item)
                                        } else if row.rowType == .liveTvOnNow || row.rowType == .liveTvComingUp {
                                            if let channelId = item.channelId {
                                                router.navigate(to: .liveTvPlayer(channelId: channelId))
                                            }
                                        } else {
                                            router.navigateToItem(item, serverId: item.effectiveServerId)
                                        }
                                    },
                                    restoredItemId: lastFocusedRowId == row.id ? lastFocusedItemId : nil,
                                    focusTrigger: {
                                        if lastFocusedRowId == row.id {
                                            return restoreRowFocusTrigger
                                        }
                                        if visibleRows.first?.id == row.id {
                                            return focusFirstRowTrigger
                                        }
                                        return 0
                                    }()
                                )
                                .id(row.id)
                                .prefersDefaultFocus(isRestoringPosition && lastFocusedRowId == row.id, in: rowsNamespace)
                            }
                        }
                        .focusScope(rowsNamespace)
                    }
                    .padding(.leading, contentLeading)
                    .padding(.trailing, 50)
                }
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 30)

                        Color.black
                    }
                )
                .onChange(of: scrollTrigger) { _ in
                    guard let id = focusedRowId else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.05))
                    }
                }
                .onChange(of: restoreScrollTrigger) { _ in
                    guard let rowId = lastFocusedRowId else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(rowId, anchor: UnitPoint(x: 0, y: 0.05))
                    }
                }
                .onAppear {
                    if let rowId = lastFocusedRowId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(rowId, anchor: UnitPoint(x: 0, y: 0.05))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func navigateToLibrary(_ item: ServerItem) {
        router.navigateToLibrary(item)
    }

    private func navigateToLiveTvAction(_ item: ServerItem) {
        switch item.id {
        case "ltv_guide":
            router.navigate(to: .liveTvGuide)
        case "ltv_recordings":
            router.navigate(to: .liveTvRecordings)
        case "ltv_schedule":
            router.navigate(to: .liveTvSchedule)
        case "ltv_series":
            router.navigate(to: .liveTvSeriesRecordings)
        default:
            break
        }
    }

    private func scheduleMediaBarTrailerPreview(for item: MediaBarSlideItem?) {
        cancelMediaBarTrailerPreview()
        guard container.userPreferences[UserPreferences.mediaBarTrailerPreview] else { return }
        guard isMediaBarMode, let item else { return }
        guard lastPreviewedMediaBarItemId != item.id else { return }

        mediaBarTrailerPreviewTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            guard isMediaBarMode else { return }
            guard container.userPreferences[UserPreferences.mediaBarTrailerPreview] else { return }
            await playTrailerFromMediaBar(item)
        }
    }

    private func cancelMediaBarTrailerPreview() {
        mediaBarTrailerPreviewTask?.cancel()
        mediaBarTrailerPreviewTask = nil
        inlineTrailerPlayer.stop()
    }

    private func resolvePreviewStreamWithTimeout(
        videoId: String,
        timeoutSeconds: Double = 8
    ) async -> YouTubeStreamResolver.ResolveResult? {
        await withTaskGroup(of: YouTubeStreamResolver.ResolveResult?.self) { group in
            group.addTask {
                await YouTubeStreamResolver.resolveStream(videoId: videoId, mode: .preview)
            }
            group.addTask {
                let nanos = UInt64(timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func mediaBarPreviewVLCOptions(isYouTube: Bool) -> [String: Any] {
        var options: [String: Any] = [
            "http-reconnect": 1,
            "network-caching": 2500,
            "file-caching": 1500,
            "live-caching": 2500,
        ]

        if !container.userPreferences[UserPreferences.previewAudioEnabled] {
            options["no-audio"] = true
        }

        if isYouTube {
            options["http-user-agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
            options["http-referrer"] = "https://www.youtube.com/"
        }

        return options
    }

    private func playTrailerFromMediaBar(_ slideItem: MediaBarSlideItem) async {
        guard let server = container.serverRepository.currentServer.value else { return }
        let client = container.serverClientFactory.client(for: server)
        guard let item = try? await client.userLibraryApi.getItem(itemId: slideItem.id) else { return }

        if let localTrailers = try? await client.userLibraryApi.getLocalTrailers(itemId: item.id),
           let localTrailer = localTrailers.first {
            let requestedBackend = PlaybackRolloutPolicy.effectiveRequestedDirective(
                requested: container.userPreferences[UserPreferences.playbackPlayerBackend],
                stage: container.userPreferences[UserPreferences.playbackMpvCanaryStage],
                localKillSwitch: container.userPreferences[UserPreferences.playbackMpvKillSwitchEnabled]
            )
            let resolver = ServerStreamResolver(client: client, requestedBackend: requestedBackend)
            let mediaSourceId = localTrailer.mediaSources?.first?.id
            if let stream = try? await resolver.resolve(
                item: localTrailer,
                mediaSourceId: mediaSourceId,
                maxBitrate: nil,
                maxAudioChannels: nil,
                audioStreamIndex: nil,
                subtitleStreamIndex: nil,
                startTimeTicks: nil
            ) {
                guard !Task.isCancelled, isMediaBarMode else { return }
                inlineTrailerPlayer.configureNetworkOptions(mediaBarPreviewVLCOptions(isYouTube: false))
                await inlineTrailerPlayer.play(streamUrl: stream.url)
                lastPreviewedMediaBarItemId = slideItem.id
                return
            }
        }

        guard let videoId = TrailerPlaybackHelper.firstYouTubeVideoId(from: item.remoteTrailers) else { return }
        guard let result = await resolvePreviewStreamWithTimeout(videoId: videoId) else { return }
        guard let streamInfo = result.stream else { return }
        guard !Task.isCancelled, isMediaBarMode else { return }

        inlineTrailerPlayer.configureNetworkOptions(mediaBarPreviewVLCOptions(isYouTube: true))
        await inlineTrailerPlayer.play(url: streamInfo.url)
        lastPreviewedMediaBarItemId = slideItem.id
    }
}

// MARK: - Media Bar Return Sentinel

private struct MediaBarReturnSentinel: UIViewRepresentable {
    let hasContent: Bool
    let onReturn: () -> Void

    func makeUIView(context: Context) -> SentinelFocusView {
        let view = SentinelFocusView()
        view.hasContent = hasContent
        view.onReturnToMediaBar = onReturn
        return view
    }

    func updateUIView(_ uiView: SentinelFocusView, context: Context) {
        uiView.hasContent = hasContent
        uiView.onReturnToMediaBar = onReturn
    }
}

private class SentinelFocusView: UIView {
    var onReturnToMediaBar: (() -> Void)?
    var hasContent = false
    private var passingThrough = false

    override var canBecomeFocused: Bool { hasContent && !passingThrough }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard isFocused else { return }

        if context.focusHeading.contains(.up) {
            DispatchQueue.main.async { [weak self] in
                self?.onReturnToMediaBar?()
            }
        } else {
            passingThrough = true
            DispatchQueue.main.async { [weak self] in
                self?.setNeedsFocusUpdate()
                self?.passingThrough = false
            }
        }
    }
}
