import SwiftUI

struct Navbar: View {
    @StateObject private var viewModel: NavbarViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var navFocusItem: NavbarItem?
    @State private var navbarHadFocus = false
    let onMoveToContent: (() -> Void)?

    init(container: AppContainer, onMoveToContent: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: NavbarViewModel(container: container))
        self.onMoveToContent = onMoveToContent
    }

    private func routeHomeAndHandoffFocus() {
        router.reset()
        onMoveToContent?()
    }

    var body: some View {
        ZStack {
            HStack {
                startSection
                Spacer()
            }
            centerSection
        }
        .padding(.leading, 32)
        .padding(.trailing, 48)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(height: 110)
        .defaultFocus($navFocusItem, .home)
        .onChange(of: navFocusItem) { newValue in
            if newValue != nil {
                if !navbarHadFocus {
                    navbarHadFocus = true
                    if newValue != .home {
                        DispatchQueue.main.async {
                            navFocusItem = .home
                        }
                        return
                    }
                }
            } else {
                navbarHadFocus = false
            }
        }
        .onMoveCommand { direction in
            if direction == .down {
                onMoveToContent?()
            }
        }
    }

    private var startSection: some View {
        UserAvatarToolbarButton(
            imageUrl: viewModel.userImageUrl,
            isFocused: navFocusItem == .user,
            onTap: {
                viewModel.switchUser()
                router.switchFlow(to: .startup)
            }
        )
        .focused($navFocusItem, equals: .user)
    }

    private var centerSection: some View {
        HStack(spacing: 6) {
            ExpandableToolbarButton(
                icon: "house",
                label: "Home",
                action: { routeHomeAndHandoffFocus() }
            )
            .focused($navFocusItem, equals: .home)

            ExpandableToolbarButton(
                icon: "magnifyingglass",
                label: "Search",
                action: { router.navigate(to: .search()) }
            )
            .focused($navFocusItem, equals: .search)

            if viewModel.showShuffle {
                ExpandableToolbarButton(
                    icon: "shuffle",
                    label: "Shuffle",
                    isAssetIcon: true,
                    action: { viewModel.performQuickShuffle(router: router) }
                )
                .focused($navFocusItem, equals: .shuffle)
                .contextMenu {
                    ForEach(ShuffleContentType.allCases, id: \.self) { type in
                        Button(type.displayName) {
                            viewModel.performShuffle(contentType: type, router: router)
                        }
                    }
                }
            }

            if viewModel.showFavorites {
                ExpandableToolbarButton(
                    icon: "heart.fill",
                    label: "Favorites",
                    action: { router.navigate(to: .allFavorites) }
                )
                .focused($navFocusItem, equals: .favorites)
            }

            if viewModel.showGenres {
                ExpandableToolbarButton(
                    icon: "theatermasks",
                    label: "Genres",
                    action: { router.navigate(to: .allGenres) }
                )
                .focused($navFocusItem, equals: .genres)
            }

            ExpandableToolbarButton(
                icon: "folder.fill",
                label: "Folders",
                action: { router.navigate(to: .folderView) }
            )
            .focused($navFocusItem, equals: .folders)

            if viewModel.showSeerrInToolbar {
                ExpandableToolbarButton(
                    icon: viewModel.seerrIconName,
                    label: viewModel.seerrDisplayName,
                    isAssetIcon: true,
                    action: { router.navigate(to: .seerrDiscover) }
                )
                .focused($navFocusItem, equals: .seerr)
            }

            if viewModel.showLibraries && !viewModel.userViews.isEmpty {
                ExpandableLibrariesButton(
                    libraries: viewModel.userViews,
                    activeLibraryId: nil,
                    onLibrarySelected: { library in
                        router.navigateToLibrary(library)
                    }
                )
                .focused($navFocusItem, equals: .libraries)
            }

            if viewModel.showSyncPlay {
                ExpandableToolbarButton(
                    icon: "person.2.fill",
                    label: "SyncPlay",
                    action: { settingsRouter.open(to: .syncPlay) }
                )
                .focused($navFocusItem, equals: .syncPlay)
            }

            ExpandableToolbarButton(
                icon: "gearshape.fill",
                label: "Settings",
                action: { settingsRouter.open() }
            )
            .focused($navFocusItem, equals: .settings)
        }
        .background(
            Capsule()
                .fill(viewModel.overlayColor.opacity(viewModel.overlayOpacity))
        )
        .clipShape(Capsule())
    }
}

private enum NavbarItem: Hashable {
    case user
    case home
    case search
    case shuffle
    case favorites
    case genres
    case folders
    case seerr
    case libraries
    case syncPlay
    case settings
}

private struct UserAvatarToolbarButton: View {
    let imageUrl: String?
    let isFocused: Bool
    let onTap: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            fallbackIcon
                        }
                    }
                } else {
                    fallbackIcon
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    private var fallbackIcon: some View {
        ZStack {
            Circle()
                .fill(theme.colorScheme.button)
            Image(systemName: "person.fill")
                .font(.system(size: 20))
                .foregroundColor(theme.colorScheme.onButton)
        }
    }
}
