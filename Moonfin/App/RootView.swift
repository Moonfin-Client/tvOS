import SwiftUI

struct RootView: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()

            switch router.flow {
            case .splash:
                SplashScreen()
            case .startup:
                StartupNavigationView()
            case .main:
                MainNavigationView()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                router.switchFlow(to: .startup)
            }
        }
    }
}

struct StartupNavigationView: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter

    var body: some View {
        NavigationStack(path: $router.path) {
            SelectServerScreen(container: container)
                .navigationDestination(for: Destination.self) { destination in
                    startupDestinationView(for: destination)
                }
        }
    }

    @ViewBuilder
    private func startupDestinationView(for destination: Destination) -> some View {
        switch destination {
        case .serverAdd:
            ServerAddScreen(container: container)
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
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var settingsRouter: SettingsRouter

    var body: some View {
        ZStack {
            NavigationStack(path: $router.path) {
                HomePlaceholderView()
                    .navigationDestination(for: Destination.self) { destination in
                        mainDestinationView(for: destination)
                    }
            }

            if settingsRouter.isPresented {
                SettingsOverlayView()
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: settingsRouter.isPresented)
    }

    @ViewBuilder
    private func mainDestinationView(for destination: Destination) -> some View {
        switch destination {
        case .home:
            HomePlaceholderView()
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

struct HomePlaceholderView: View {
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            Image(systemName: "house.fill")
                .font(.system(size: 60))
                .foregroundColor(theme.accent)
            Text("Home")
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground)
        }
    }
}

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
