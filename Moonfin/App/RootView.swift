import SwiftUI
import AVKit

struct RootView: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var sessionInitializer: SessionInitializer

    var body: some View {
        ZStack {
            LoginBackground()

            switch router.flow {
            case .splash:
                SplashScreen()
                    .transition(.opacity)
            case .startup:
                StartupNavigationView()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .identity
                    ))
            case .main:
                MainNavigationView()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .identity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.5), value: router.flow)
        .onAppear {
            sessionInitializer.initialize(router: router)
        }
    }
}

struct StartupNavigationView: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var sessionInitializer: SessionInitializer

    var body: some View {
        NavigationStack(path: $router.path) {
            SelectServerScreen(container: container)
                .navigationDestination(for: Destination.self) { destination in
                    startupDestinationView(for: destination)
                }
        }
        .onAppear {
            if let serverId = sessionInitializer.restoredServerId {
                sessionInitializer.restoredServerId = nil
                router.navigate(to: .serverUsers(serverId: serverId))
            }
        }
    }

    @ViewBuilder
    private func startupDestinationView(for destination: Destination) -> some View {
        switch destination {
        case .serverAdd:
            ServerAddScreen(container: container)
        case .embyConnect:
            EmbyConnectScreen(container: container)
        case .serverUsers(let serverId):
            ServerScreen(serverId: serverId, container: container)
        case .userLogin(let serverId, let username):
            UserLoginScreen(serverId: serverId, username: username, container: container)
        case .connectHelp:
            ConnectHelpScreen()
        default:
            PlaceholderView(title: "Screen")
        }
    }
}

struct MainNavigationView: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @Namespace private var mainNamespace
    @Namespace private var settingsNamespace
    @Environment(\.resetFocus) private var resetFocus
    @State private var contentReady = false
    @State private var sidebarEntryToken = 0
    @State private var sidebarHandoffToken = 0
    @State private var suppressTopNavbarInRows = false
    @State private var navbarHomeFocusToken = 0
    @State private var preferContentFocusDuringHandoff = false
    @State private var isCurrentDestinationDetails = false
    @State private var contentHandoffResetTask: Task<Void, Never>?
    @State private var showExitConfirmation = false

    private var navbarPosition: NavbarPosition {
        container.userPreferences[UserPreferences.navbarPosition]
    }

    private let navbarHeight: CGFloat = 110

    private var shouldShowTopNavbar: Bool {
        guard !router.hideNavbar else { return false }
        if !router.path.isEmpty { return true }
        return !suppressTopNavbarInRows
    }

    private var contentShouldPreferDefaultFocus: Bool {
        switch navbarPosition {
        case .top:
            return !shouldShowTopNavbar
        case .left:
            return true
        }
    }

    private var isLeftNavbarDetails: Bool {
        navbarPosition == .left && isCurrentDestinationDetails
    }

    private func scheduleContentHandoffReset() {
        contentHandoffResetTask?.cancel()
        contentHandoffResetTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            preferContentFocusDuringHandoff = false
        }
    }

    private func handoffSidebarFocusToContent() {
        let isTopNavbarHome = navbarPosition == .top && router.path.isEmpty
        guard !isTopNavbarHome else { return }
        preferContentFocusDuringHandoff = true
        sidebarHandoffToken += 1
        let isLeftNavbarHome = navbarPosition == .left && router.path.isEmpty
        let shouldSkipResetFocus = isLeftNavbarHome || isLeftNavbarDetails
        if !shouldSkipResetFocus {
            DispatchQueue.main.async {
                resetFocus(in: mainNamespace)
            }
        }
        scheduleContentHandoffReset()
    }

    private func noteSidebarEntered() {
        sidebarEntryToken += 1
    }

    private func handoffSettingsFocusToContent() {
        preferContentFocusDuringHandoff = true
        sidebarHandoffToken += 1
        DispatchQueue.main.async {
            resetFocus(in: mainNamespace)
        }
        scheduleContentHandoffReset()
    }

    private func requestNavbarHomeFocus() {
        guard navbarPosition == .top, shouldShowTopNavbar else { return }
        navbarHomeFocusToken += 1
    }

    var body: some View {
        ZStack {
            mainContent
                .focusSection()
                .prefersDefaultFocus(contentShouldPreferDefaultFocus, in: mainNamespace)
                .disabled(settingsRouter.isPresented || container.inactivityTracker.isScreensaverVisible || showExitConfirmation)

            navigationOverlay
                .opacity(container.inactivityTracker.isScreensaverVisible ? 0 : 1)
                .disabled(settingsRouter.isPresented || container.inactivityTracker.isScreensaverVisible || showExitConfirmation)

            clockOverlay

            if settingsRouter.isPresented {
                theme.colorScheme.scrim
                    .ignoresSafeArea()
                    .transition(.opacity)

                SettingsOverlayView(focusNamespace: settingsNamespace)
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing))
                    .prefersDefaultFocus(in: mainNamespace)
            }

            if container.inactivityTracker.isScreensaverVisible {
                ScreensaverView(container: container) {
                    container.inactivityTracker.notifyInteraction()
                }
                .transition(.opacity)
                .focusSection()
                .onExitCommand { container.inactivityTracker.notifyInteraction() }
            }

            if showExitConfirmation {
                theme.colorScheme.scrim
                    .ignoresSafeArea()
                    .transition(.opacity)

                ExitConfirmationDialog(
                    onConfirm: closeApp,
                    onDismiss: { showExitConfirmation = false }
                )
                .zIndex(2)
            }
        }
        .ignoresSafeArea()
        .focusScope(mainNamespace)
        .animation(.easeInOut(duration: 0.4), value: settingsRouter.isPresented)
        .animation(.easeInOut(duration: 1.0), value: container.inactivityTracker.isScreensaverVisible)
        .onChange(of: settingsRouter.isPresented) { presented in
            container.inactivityTracker.notifyInteraction()
            if presented {
                container.inactivityTracker.addLock()
                showExitConfirmation = false
                DispatchQueue.main.async {
                    resetFocus(in: mainNamespace)
                }
            } else {
                container.inactivityTracker.removeLock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    handoffSettingsFocusToContent()
                }
            }
        }
        .onChange(of: container.inactivityTracker.isScreensaverVisible) { visible in
            if !visible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    resetFocus(in: mainNamespace)
                }
            }
        }
        .onDisappear {
            contentHandoffResetTask?.cancel()
        }
        .onChange(of: router.path.count) { count in
            guard count == 0 else { return }
            if router.hideNavbar {
                router.resetNavbarVisibility()
            }
            if suppressTopNavbarInRows {
                suppressTopNavbarInRows = false
            }
        }
        .onMoveCommand { _ in
            if !container.inactivityTracker.isScreensaverVisible {
                container.inactivityTracker.notifyInteraction()
            }
        }
        .onExitCommand {
            if showExitConfirmation {
                showExitConfirmation = false
                return
            }

            if !router.path.isEmpty {
                router.goBack()
                return
            }

            guard !container.inactivityTracker.isScreensaverVisible,
                  !settingsRouter.isPresented,
                  router.path.isEmpty else { return }

            container.inactivityTracker.notifyInteraction()
            showExitConfirmation = true
        }
    }

    private func closeApp() {
        exit(0)
    }

    private var mainContent: some View {
        NavigationStack(path: $router.path) {
            HomeScreen(
                container: container,
                mainNamespace: mainNamespace,
                contentReady: $contentReady,
                sidebarEntryToken: sidebarEntryToken,
                sidebarHandoffToken: sidebarHandoffToken,
                suppressTopNavbarInRows: $suppressTopNavbarInRows,
                onRequestTopNavbarHomeFocus: requestNavbarHomeFocus
            )
            .onAppear {
                router.resetNavbarVisibility()
            }
                .navigationDestination(for: Destination.self) { destination in
                    mainDestinationView(for: destination)
                }
        }
    }

    @ViewBuilder
    private var navigationOverlay: some View {
        switch navbarPosition {
        case .top:
            if shouldShowTopNavbar {
                VStack(spacing: 0) {
                    Navbar(
                        container: container,
                        requestHomeFocusToken: navbarHomeFocusToken,
                        onMoveToContent: handoffSidebarFocusToContent
                    )
                        .frame(height: navbarHeight)
                        .focusSection()
                        .prefersDefaultFocus(true, in: mainNamespace)
                    Spacer()
                }
                .zIndex(1)
            }
        case .left:
            if contentReady && !router.hideNavbar {
                LeftSidebar(
                    container: container,
                    onMoveToContent: handoffSidebarFocusToContent,
                    onSidebarEntered: noteSidebarEntered
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ignoresSafeArea()
                    .zIndex(1)
            }
        }
    }

    // MARK: - Clock overlay

    @ViewBuilder
    private var clockOverlay: some View {
        let clock = container.userPreferences[UserPreferences.clockBehavior]
        if clock == .always
            || (clock == .inNavOnly && !router.hideNavbar)
            || (clock == .inVideo && router.hideNavbar) {
            VStack {
                HStack {
                    Spacer()
                    ToolbarClock()
                        .frame(height: navbarHeight)
                        .padding(.trailing, 8)
                }
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func mainDestinationView(for destination: Destination) -> some View {
        switch destination {
        case .home:
            HomeScreen(
                container: container,
                mainNamespace: mainNamespace,
                sidebarEntryToken: sidebarEntryToken,
                sidebarHandoffToken: sidebarHandoffToken,
                suppressTopNavbarInRows: $suppressTopNavbarInRows,
                onRequestTopNavbarHomeFocus: requestNavbarHomeFocus
            )
        case .search(let query):
            SearchScreen(container: container, query: query)
        case .libraryBrowser(let itemId, _, let serverId, _):
            LibraryBrowseScreen(container: container, parentId: itemId, serverId: serverId)
        case .libraryBrowserByType(let itemId, let includeType):
            LibraryBrowseScreen(
                container: container,
                parentId: itemId,
                includeTypes: [ItemType(rawValue: includeType) ?? .movie]
            )
        case .collectionBrowser(let itemId, let serverId, _):
            LibraryBrowseScreen(container: container, parentId: itemId, serverId: serverId)
        case .allFavorites:
            FavoritesScreen(container: container)
        case .librarySuggestions(let itemId):
            SuggestedScreen(container: container, parentId: itemId)
        case .allGenres:
            GenreBrowseScreen(container: container)
        case .genreBrowse(let genreName, let parentId, let includeType, let serverId):
            LibraryBrowseScreen(
                container: container,
                parentId: parentId ?? "",
                serverId: serverId,
                includeTypes: includeType.flatMap { ItemType(rawValue: $0) }.map { [$0] },
                genreName: genreName
            )
        case .libraryByGenres(let itemId, let includeType):
            GenreBrowseScreen(container: container, parentId: itemId, includeType: includeType)
        case .libraryByLetter(let itemId, let includeType):
            LibraryBrowseScreen(
                container: container,
                parentId: itemId,
                includeTypes: [ItemType(rawValue: includeType) ?? .movie]
            )
        case .musicBrowser(let itemId, let serverId, _):
            MusicBrowseScreen(container: container, parentId: itemId, serverId: serverId)
        case .folderView:
            FolderBrowseScreen(container: container)
        case .folderBrowser(let itemId, _, _):
            FolderBrowseScreen(container: container, folderId: itemId)
        case .itemDetails(let itemId, let serverId):
            ItemDetailsView(
                container: container,
                itemId: itemId,
                serverId: serverId,
                sidebarEntryToken: sidebarEntryToken,
                sidebarHandoffToken: sidebarHandoffToken
            )
            .onAppear { isCurrentDestinationDetails = true }
            .onDisappear { isCurrentDestinationDetails = false }
        case .nowPlaying:
            audioPlayerDestination
        case .photoPlayer(let itemId, let autoPlay, let sortBy, let sortOrder):
            PhotoPlayerScreen(
                container: container,
                itemId: itemId,
                autoPlay: autoPlay,
                sortBy: sortBy,
                sortOrder: sortOrder
            )
        case .bookReader(let itemId, let serverId):
            BookReaderScreen(container: container, itemId: itemId, serverId: serverId)
        case .videoPlayer:
            videoPlayerDestination
        case .trailerPlayer(let videoId, let startSeconds, let segmentsJson):
            TrailerPlayerScreen(videoId: videoId, startSeconds: startSeconds, segmentsJson: segmentsJson)
        case .liveTvGuide:
            LiveTvGuideView(container: container)
        case .liveTvRecordings:
            RecordingsView(container: container)
        case .liveTvSeriesRecordings:
            RecordingsView(container: container, initialTab: .series)
        case .liveTvSchedule:
            RecordingsView(container: container, initialTab: .scheduled)
        case .liveTvPlayer(let channelId):
            liveTvPlayerDestination(channelId: channelId)
        case .seerrDiscover:
            SeerrDiscoverView(seerrRepository: container.seerrRepository)
        case .seerrMediaDetails(let itemJson):
            SeerrMediaDetailsView(itemJson: itemJson, seerrRepository: container.seerrRepository)
        case .seerrPersonDetails(let personId):
            SeerrPersonDetailsView(personId: personId, seerrRepository: container.seerrRepository)
        case .seerrBrowseBy(let filterId, let filterName, let mediaType, let filterType):
            SeerrBrowseByView(filterId: filterId, filterName: filterName, mediaType: mediaType,
                              filterType: filterType, seerrRepository: container.seerrRepository)
        default:
            PlaceholderView(title: "Screen")
        }
    }

    @ViewBuilder
    private var videoPlayerDestination: some View {
        if let manager = container.playbackCoordinator.videoPlayerManager {
            VideoPlayerScreen(playbackManager: manager)
                .onAppear { router.pushNavbarHidden() }
                .onDisappear {
                    router.popNavbarHidden()
                    Task { await container.playbackCoordinator.stopVideoPlayback() }
                }
        } else {
            PlaceholderView(title: "Video Player")
        }
    }

    @ViewBuilder
    private var audioPlayerDestination: some View {
        if let audio = container.playbackCoordinator.audioManager,
           let server = container.serverRepository.currentServer.value {
            let client = container.serverClientFactory.client(for: server)
            AudioNowPlayingView(
                viewModel: AudioNowPlayingViewModel(audioManager: audio, client: client)
            )
            .onAppear { router.pushNavbarHidden() }
            .onDisappear { router.popNavbarHidden() }
        } else {
            PlaceholderView(title: "Now Playing")
        }
    }

    @ViewBuilder
    private func liveTvPlayerDestination(channelId: String) -> some View {
        if let manager = container.playbackCoordinator.videoPlayerManager {
            VideoPlayerScreen(
                playbackManager: manager,
                isLiveTV: true,
                onLiveTvChannelUp: { await switchLiveTvChannel(by: -1) },
                onLiveTvChannelDown: { await switchLiveTvChannel(by: 1) }
            )
                .onAppear { router.pushNavbarHidden() }
                .onDisappear {
                    router.popNavbarHidden()
                    Task { await container.playbackCoordinator.stopVideoPlayback() }
                }
        } else {
            PlaceholderView(title: "Live TV Player")
        }
    }

    private func switchLiveTvChannel(by delta: Int) async {
        guard let nextChannel = container.playbackCoordinator.stepLiveTvChannel(by: delta),
              let manager = container.playbackCoordinator.videoPlayerManager else { return }
        await manager.play(items: [nextChannel])
    }
}

private struct ExitConfirmationDialog: View {
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    private enum DialogFocusTarget: Hashable {
        case cancel
        case exit
    }

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedTarget: DialogFocusTarget?

    var body: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 40))
                .foregroundColor(theme.accent)

            Text(Strings.exitConfirmTitle)
                .font(.titleMd)
                .foregroundColor(theme.colorScheme.onBackground)

            Text(Strings.exitConfirmMessage)
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                .multilineTextAlignment(.center)

            HStack(spacing: SpaceTokens.spaceMd) {
                FocusableDialogButton(title: Strings.cancel, action: onDismiss)
                    .focused($focusedTarget, equals: .cancel)
                FocusableDialogButton(title: Strings.exit, action: onConfirm)
                    .focused($focusedTarget, equals: .exit)
            }
        }
        .padding(SpaceTokens.spaceXl)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(theme.colorScheme.surface)
        )
        .frame(maxWidth: 500)
        .focusSection()
        .onAppear {
            DispatchQueue.main.async {
                focusedTarget = .cancel
            }
        }
        .onExitCommand(perform: onDismiss)
    }
}

struct PlaceholderView: View {
    let title: String
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack {
            Text(title)
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground)
        }
    }
}

struct TrailerPlayerScreen: View {
    let videoId: String
    let startSeconds: Double
    let segmentsJson: String

    @EnvironmentObject var router: NavigationRouter
    @StateObject private var player: VLCPlayerWrapper
    @State private var hasStartedPlayback = false
    @State private var resolveError: String?
    @State private var resolverDiagnostics: String = ""
    @State private var sponsorSegments: [SponsorBlockAPI.Segment] = []
    @State private var effectiveStartSeconds: Double = 0
    @State private var playbackWatchdogTask: Task<Void, Never>?
    @State private var resolvedStreamURL: URL?
    @State private var didTryNativeFallback = false
    @State private var nativePlayer: AVPlayer?

    init(videoId: String, startSeconds: Double, segmentsJson: String) {
        self.videoId = videoId
        self.startSeconds = startSeconds
        self.segmentsJson = segmentsJson
        _player = StateObject(wrappedValue: MpvPlayerWrapper.makePreferredPlayer())
    }

    private var isLoading: Bool {
        switch player.state {
        case .idle, .opening, .buffering:
            return resolveError == nil
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let nativePlayer {
                VideoPlayer(player: nativePlayer)
                    .ignoresSafeArea()
                    .onAppear {
                        nativePlayer.play()
                    }
            } else {
                VLCPlayerView(player: player)
                    .ignoresSafeArea()
                    .id(videoId)
            }

            if isLoading {
                VStack(spacing: SpaceTokens.spaceMd) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading trailer...")
                        .font(.titleLg)
                        .foregroundColor(.white.opacity(0.9))
                }
            }

            if let resolveError {
                ScrollView {
                    VStack(spacing: SpaceTokens.spaceMd) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2xl)
                            .foregroundColor(.yellow)
                        Text("Unable to play trailer")
                            .font(.titleLg)
                            .foregroundColor(.white)
                        Text(resolveError)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, SpaceTokens.spaceXl)
                    }
                    .padding(SpaceTokens.spaceLg)
                }
            }

            if player.state == .error && resolveError == nil {
                VStack(spacing: SpaceTokens.spaceMd) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2xl)
                        .foregroundColor(.yellow)
                    Text("Trailer playback failed")
                        .font(.titleLg)
                        .foregroundColor(.white)
                }
                .padding(SpaceTokens.spaceLg)
            }
        }
        .onAppear {
            router.pushNavbarHidden()
        }
        .onDisappear {
            playbackWatchdogTask?.cancel()
            player.stop()
            nativePlayer?.pause()
            nativePlayer = nil
            router.popNavbarHidden()
        }
        .task {
            guard !hasStartedPlayback else { return }
            hasStartedPlayback = true
            await resolveAndPlay()
        }
        .onChange(of: player.currentTime) { currentTime in
            skipSponsorSegmentsIfNeeded(currentTime: currentTime)
        }
        .onChange(of: player.state) { newState in
            if newState == .error && resolveError == nil {
                attemptNativeFallbackOrFail(reason: "VLC state: \(stateDescription(newState))")
            }
        }
        .onExitCommand {
            playbackWatchdogTask?.cancel()
            player.stop()
            nativePlayer?.pause()
            router.goBack()
        }
    }

    private func resolveAndPlay() async {
        async let streamTask = YouTubeStreamResolver.resolveStream(videoId: videoId)
        async let segmentsTask = SponsorBlockAPI.getSkipSegments(videoId: videoId)

        let segments = await segmentsTask
        sponsorSegments = segments
        effectiveStartSeconds = SponsorBlockAPI.calculateStartTime(segments: segments)

        let result = await streamTask
        resolverDiagnostics = result.diagnostics
        guard let streamInfo = result.stream else {
            resolveError = "Could not resolve a playable stream.\n\n\(result.diagnostics)"
            return
        }
        resolvedStreamURL = streamInfo.url

        player.configureNetworkOptions([
            "http-user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
            "http-referrer": "https://www.youtube.com/",
            "http-reconnect": 1,
            "network-caching": 1000,
        ])

        if effectiveStartSeconds > 0 {
            await player.play(streamUrl: streamInfo.url.absoluteString, startPosition: effectiveStartSeconds)
        } else {
            await player.play(url: streamInfo.url)
        }

        startPlaybackWatchdog(streamURL: streamInfo.url)
    }

    private func startPlaybackWatchdog(streamURL: URL) {
        playbackWatchdogTask?.cancel()
        playbackWatchdogTask = Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 250_000_000)

                if Task.isCancelled { return }

                switch player.state {
                case .playing, .paused:
                    return
                case .error:
                    attemptNativeFallbackOrFail(
                        reason: "VLC state: \(stateDescription(player.state))\nURL host: \(streamURL.host ?? "unknown")"
                    )
                    return
                default:
                    break
                }
            }

            if resolveError == nil {
                attemptNativeFallbackOrFail(
                    reason: "VLC state: \(stateDescription(player.state))\nURL host: \(streamURL.host ?? "unknown")"
                )
            }
        }
    }

    @MainActor
    private func attemptNativeFallbackOrFail(reason: String) {
        if !didTryNativeFallback, let streamURL = resolvedStreamURL {
            didTryNativeFallback = true
            player.stop()

            let av = AVPlayer(url: streamURL)
            nativePlayer = av

            if effectiveStartSeconds > 0 {
                let target = CMTime(seconds: effectiveStartSeconds, preferredTimescale: 600)
                av.seek(to: target)
            }
            av.play()

            playbackWatchdogTask?.cancel()
            playbackWatchdogTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                guard let player = nativePlayer else { return }

                if player.timeControlStatus != .playing {
                    resolveError = "Trailer playback failed after stream resolution.\n\n\(reason)\nAVPlayer status: \(player.status == .failed ? "failed" : "not-playing")\n\n\(resolverDiagnostics)"
                }
            }
            return
        }

        if resolveError == nil {
            resolveError = "Trailer playback failed after stream resolution.\n\n\(reason)\n\n\(resolverDiagnostics)"
        }
    }

    private func stateDescription(_ state: VLCPlayerState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .opening:
            return "opening"
        case .buffering(let progress):
            return String(format: "buffering(%.2f)", progress)
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .stopped:
            return "stopped"
        case .ended:
            return "ended"
        case .error:
            return "error"
        }
    }

    private func skipSponsorSegmentsIfNeeded(currentTime: TimeInterval) {
        guard !sponsorSegments.isEmpty else { return }
        for segment in sponsorSegments {
            if currentTime >= segment.startTime && currentTime < segment.endTime - 0.5 {
                player.seek(to: segment.endTime)
                break
            }
        }
    }
}
