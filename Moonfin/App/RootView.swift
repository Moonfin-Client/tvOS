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
                        Navbar(container: container)
                            .frame(height: navbarHeight)
                            .focusSection()
                            .zIndex(1)

                        mainContent
                            .focusSection()
                            .offset(y: -navbarHeight)
                            .padding(.bottom, -navbarHeight)
                    }
                    .ignoresSafeArea(edges: .top)
                case .left:
                    ZStack {
                        mainContent
                            .focusSection()
                        LeftSidebar(container: container)
                            .focusSection()
                    }
                }
            }
            .disabled(settingsRouter.isPresented)

            if settingsRouter.isPresented {
                theme.colorScheme.scrim
                    .ignoresSafeArea()
                    .transition(.opacity)

                SettingsOverlayView(focusNamespace: mainNamespace)
                    .transition(.move(edge: .trailing))
            }
        }
        .focusScope(mainNamespace)
        .animation(.easeInOut(duration: 0.4), value: settingsRouter.isPresented)
        .onChange(of: settingsRouter.isPresented) { presented in
            if presented {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    resetFocus(in: mainNamespace)
                }
            }
        }
    }

    private var mainContent: some View {
        NavigationStack(path: $router.path) {
            HomeScreen(container: container, mainNamespace: mainNamespace)
                .navigationDestination(for: Destination.self) { destination in
                    mainDestinationView(for: destination)
                }
        }
        .prefersDefaultFocus(in: mainNamespace)
    }

    @ViewBuilder
    private func mainDestinationView(for destination: Destination) -> some View {
        switch destination {
        case .home:
            HomeScreen(container: container, mainNamespace: mainNamespace)
        case .search:
            PlaceholderView(title: "Search")
        case .libraryBrowser:
            PlaceholderView(title: "Library")
        case .itemDetails(let itemId, _):
            PlaceholderView(title: "Item: \(itemId)")
        case .nowPlaying:
            PlaceholderView(title: "Now Playing")
        case .videoPlayer:
            PlaceholderView(title: "Video Player")
        case .liveTvGuide:
            PlaceholderView(title: "Live TV Guide")
        case .jellyseerrDiscover:
            PlaceholderView(title: "Discover")
        default:
            PlaceholderView(title: "Screen")
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
