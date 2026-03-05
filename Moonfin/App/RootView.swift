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
    @AppStorage("navbar_position") private var navbarPosition: NavbarPosition = .top

    var body: some View {
        ZStack {
            switch navbarPosition {
            case .top:
                mainContent
                    .overlay(alignment: .top) {
                        Navbar(container: container)
                            .ignoresSafeArea(edges: .top)
                    }
            case .left:
                ZStack {
                    mainContent
                    LeftSidebar(container: container)
                }
            }

            if settingsRouter.isPresented {
                SettingsOverlayView()
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: settingsRouter.isPresented)
    }

    private var mainContent: some View {
        NavigationStack(path: $router.path) {
            HomeScreen(container: container)
                .navigationDestination(for: Destination.self) { destination in
                    mainDestinationView(for: destination)
                }
        }
    }

    @ViewBuilder
    private func mainDestinationView(for destination: Destination) -> some View {
        switch destination {
        case .home:
            HomeScreen(container: container)
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

// MARK: - Placeholders

struct SettingsOverlayView: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var settingsRouter: SettingsRouter

    var body: some View {
        HStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: RadiusTokens.large, style: .continuous)
                    .fill(theme.colorScheme.surface)
                    .frame(width: 350)

                VStack(spacing: SpaceTokens.spaceMd) {
                    Text("Settings")
                        .font(.titleXl)
                        .foregroundColor(theme.colorScheme.onBackground)
                    Text("Phase 4 will implement settings screens")
                        .font(.bodySm)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                }
                .frame(width: 350)
            }
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
