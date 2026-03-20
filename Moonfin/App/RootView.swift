import SwiftUI

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
    @Environment(\.resetFocus) private var resetFocus
    @State private var contentReady = false
    @State private var sidebarHandoffToken = 0

    private var navbarPosition: NavbarPosition {
        container.userPreferences[UserPreferences.navbarPosition]
    }

    private let navbarHeight: CGFloat = 110

    private func handoffSidebarFocusToContent() {
        sidebarHandoffToken += 1
        DispatchQueue.main.async {
            resetFocus(in: mainNamespace)
        }
    }

    private func handoffSettingsFocusToContent() {
        sidebarHandoffToken += 1
        DispatchQueue.main.async {
            resetFocus(in: mainNamespace)
        }
    }

    var body: some View {
        ZStack {
            // --- Main content layer: NavigationStack is ALWAYS here,
            //     never inside a switch or conditional that could change.
            mainContent
                .focusSection()
                .prefersDefaultFocus(in: mainNamespace)
                .disabled(settingsRouter.isPresented || container.inactivityTracker.isScreensaverVisible)

            // --- Navigation overlay (navbar or sidebar) rendered on top
            navigationOverlay
                .disabled(settingsRouter.isPresented || container.inactivityTracker.isScreensaverVisible)

            // --- Clock overlay
            clockOverlay

            // --- Settings sheet
            if settingsRouter.isPresented {
                theme.colorScheme.scrim
                    .ignoresSafeArea()
                    .transition(.opacity)

                SettingsOverlayView(focusNamespace: mainNamespace)
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing))
            }

            // --- Screensaver
            if container.inactivityTracker.isScreensaverVisible {
                ScreensaverView(container: container) {
                    container.inactivityTracker.notifyInteraction()
                }
                .transition(.opacity)
                .focusSection()
                .onExitCommand { container.inactivityTracker.notifyInteraction() }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
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
        .onMoveCommand { _ in
            if !container.inactivityTracker.isScreensaverVisible {
                container.inactivityTracker.notifyInteraction()
            }
        }
    }

    // MARK: - Stable NavigationStack (never recreated)

    private var mainContent: some View {
        NavigationStack(path: $router.path) {
            HomeScreen(
                container: container,
                mainNamespace: mainNamespace,
                contentReady: $contentReady,
                sidebarHandoffToken: sidebarHandoffToken
            )
                .navigationDestination(for: Destination.self) { destination in
                    mainDestinationView(for: destination)
                }
        }
    }

    // MARK: - Navigation overlay (changes freely without affecting NavigationStack)

    @ViewBuilder
    private var navigationOverlay: some View {
        switch navbarPosition {
        case .top:
            if !router.hideNavbar {
                VStack(spacing: 0) {
                    Navbar(container: container, onMoveToContent: handoffSidebarFocusToContent)
                        .frame(height: navbarHeight)
                        .focusSection()
                    Spacer()
                }
                .zIndex(1)
            }
        case .left:
            if contentReady && !router.hideNavbar {
                LeftSidebar(
                    container: container,
                    mainNamespace: mainNamespace,
                    onMoveToContent: handoffSidebarFocusToContent
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
                sidebarHandoffToken: sidebarHandoffToken
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
        case .musicBrowser(let itemId, let serverId, _):
            MusicBrowseScreen(container: container, parentId: itemId, serverId: serverId)
        case .folderView:
            FolderBrowseScreen(container: container)
        case .folderBrowser(let itemId, _, _):
            FolderBrowseScreen(container: container, folderId: itemId)
        case .itemDetails(let itemId, let serverId):
            ItemDetailsView(container: container, itemId: itemId, serverId: serverId)
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
        case .videoPlayer:
            videoPlayerDestination
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
                .onAppear { router.hideNavbar = true }
                .onDisappear {
                    router.hideNavbar = false
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
        } else {
            PlaceholderView(title: "Now Playing")
        }
    }

    @ViewBuilder
    private func liveTvPlayerDestination(channelId: String) -> some View {
        if let manager = container.playbackCoordinator.videoPlayerManager {
            VideoPlayerScreen(playbackManager: manager, isLiveTV: true)
                .onAppear { router.hideNavbar = true }
                .onDisappear {
                    Task { await container.playbackCoordinator.stopVideoPlayback() }
                }
        } else {
            PlaceholderView(title: "Live TV Player")
        }
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
