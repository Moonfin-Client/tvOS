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
                    .transition(.opacity)
            case .main:
                MainNavigationView()
                    .transition(.opacity)
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
    @AppStorage("navbar_position") private var navbarPosition: NavbarPosition = .top
    @Namespace private var mainNamespace
    @Environment(\.resetFocus) private var resetFocus

    private let navbarHeight: CGFloat = 110

    var body: some View {
        ZStack {
            Group {
                switch navbarPosition {
                case .top:
                    VStack(spacing: 0) {
                        if !router.hideNavbar {
                            Navbar(container: container)
                                .frame(height: navbarHeight)
                                .focusSection()
                                .zIndex(1)
                        }

                        mainContent
                            .focusSection()
                            .prefersDefaultFocus(in: mainNamespace)
                            .offset(y: router.hideNavbar ? 0 : -navbarHeight)
                            .padding(.bottom, router.hideNavbar ? 0 : -navbarHeight)
                    }
                    .ignoresSafeArea(edges: .top)
                case .left:
                    ZStack(alignment: .leading) {
                        mainContent
                            .focusSection()
                            .prefersDefaultFocus(in: mainNamespace)
                        if !router.hideNavbar {
                            LeftSidebar(container: container, mainNamespace: mainNamespace)
                                .ignoresSafeArea()
                                .zIndex(1)
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            .disabled(settingsRouter.isPresented)
            .overlay(alignment: .topTrailing) {
                let clock = container.userPreferences[UserPreferences.clockBehavior]
                if clock == .always
                    || (clock == .inNavOnly && !router.hideNavbar)
                    || (clock == .inVideo && router.hideNavbar) {
                    ToolbarClock()
                        .frame(height: navbarHeight)
                        .padding(.trailing, 8)
                        .ignoresSafeArea()
                }
            }

            if settingsRouter.isPresented {
                theme.colorScheme.scrim
                    .ignoresSafeArea()
                    .transition(.opacity)

                SettingsOverlayView(focusNamespace: mainNamespace)
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing))
            }

            if container.inactivityTracker.isScreensaverVisible {
                ScreensaverView(container: container) {
                    container.inactivityTracker.notifyInteraction()
                }
                .transition(.opacity)
            }
        }
        .focusScope(mainNamespace)
        .animation(.easeInOut(duration: 0.4), value: settingsRouter.isPresented)
        .animation(.easeInOut(duration: 1.0), value: container.inactivityTracker.isScreensaverVisible)
        .onChange(of: settingsRouter.isPresented) { presented in
            container.inactivityTracker.notifyInteraction()
            if presented {
                container.inactivityTracker.addLock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    resetFocus(in: mainNamespace)
                }
            } else {
                container.inactivityTracker.removeLock()
            }
        }
        .onMoveCommand { _ in
            container.inactivityTracker.notifyInteraction()
        }
    }

    private var mainContent: some View {
        NavigationStack(path: $router.path) {
            HomeScreen(container: container, mainNamespace: mainNamespace)
                .navigationDestination(for: Destination.self) { destination in
                    mainDestinationView(for: destination)
                }
        }
    }

    @ViewBuilder
    private func mainDestinationView(for destination: Destination) -> some View {
        switch destination {
        case .home:
            HomeScreen(container: container, mainNamespace: mainNamespace)
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
