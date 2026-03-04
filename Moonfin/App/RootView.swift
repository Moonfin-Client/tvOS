import SwiftUI

struct RootView: View {
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()

            switch router.flow {
            case .splash:
                SplashView()
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

struct SplashView: View {
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(theme.accent)
            Text("Moonfin")
                .font(.title3xl)
                .foregroundColor(theme.colorScheme.onBackground)
        }
    }
}

struct StartupNavigationView: View {
    @EnvironmentObject var router: NavigationRouter

    var body: some View {
        NavigationStack(path: $router.path) {
            StartupPlaceholderView()
                .navigationDestination(for: Destination.self) { destination in
                    destinationView(for: destination)
                }
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
                        destinationView(for: destination)
                    }
            }

            if settingsRouter.isPresented {
                SettingsOverlayView()
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: settingsRouter.isPresented)
    }
}

@ViewBuilder
private func destinationView(for destination: Destination) -> some View {
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

// MARK: - Placeholders

struct StartupPlaceholderView: View {
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundColor(theme.accent)
            Text("Select Server")
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground)
            Text("Phase 1 will implement server selection & login")
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
        }
    }
}

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
