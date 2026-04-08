import SwiftUI

struct Navbar: View {
    @StateObject private var viewModel: NavbarViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var sessionInitializer: SessionInitializer
    @FocusState private var navFocusItem: NavbarItem?
    @Namespace private var navPillNamespace
    @State private var lockToHomeOnEntry = true
    @State private var relockTask: Task<Void, Never>?
    @State private var isLibrariesIconFocused = true
    @State private var showShuffleDialog = false
    private let navbarPillHeight: CGFloat = 56
    let requestHomeFocusToken: Int
    let onMoveToContent: (() -> Void)?

    init(container: AppContainer, requestHomeFocusToken: Int = 0, onMoveToContent: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: NavbarViewModel(container: container))
        self.requestHomeFocusToken = requestHomeFocusToken
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
        .onAppear {
            relockTask?.cancel()
            lockToHomeOnEntry = true
        }
        .onMoveCommand { direction in
            guard direction == .down else { return }
            onMoveToContent?()
        }
        .onChange(of: navFocusItem) { newValue in
            relockTask?.cancel()

            if let focused = newValue {
                if focused == .home && lockToHomeOnEntry {
                    lockToHomeOnEntry = false
                }
            } else {
                relockTask = Task {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled, navFocusItem == nil else { return }
                    await MainActor.run {
                        lockToHomeOnEntry = true
                    }
                }
            }
        }
        .onChange(of: requestHomeFocusToken) { token in
            guard token > 0 else { return }
            relockTask?.cancel()
            lockToHomeOnEntry = true
            if navFocusItem == .home {
                lockToHomeOnEntry = false
            } else {
                DispatchQueue.main.async {
                    if navFocusItem != .home {
                        navFocusItem = .home
                    }
                }
            }
        }
        .sheet(isPresented: $showShuffleDialog) {
            ShuffleOptionsDialog(
                libraries: viewModel.userViews,
                onQuickShuffle: {
                    showShuffleDialog = false
                    viewModel.performShuffle(router: router)
                },
                onLibraryShuffle: { libraryId in
                    showShuffleDialog = false
                    viewModel.performShuffle(libraryId: libraryId, router: router)
                },
                onGenreShuffle: { genreName in
                    showShuffleDialog = false
                    viewModel.performShuffle(genreName: genreName, router: router)
                },
                onDismiss: { showShuffleDialog = false },
                fetchGenres: { await viewModel.fetchGenres() }
            )
        }
    }

    private var startSection: some View {
        UserAvatarToolbarButton(
            imageUrl: viewModel.userImageUrl,
            isFocused: navFocusItem == .user,
            onTap: {
                let serverId = viewModel.switchUser()
                sessionInitializer.suppressAutoLogin = true
                sessionInitializer.restoredServerId = serverId
                router.switchFlow(to: .startup)
            }
        )
        .disabled(lockToHomeOnEntry)
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
            .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.home, in: navPillNamespace, isSource: true))

            Group {
                ExpandableToolbarButton(
                    icon: "magnifyingglass",
                    label: "Search",
                    action: { router.navigatePrimary(to: .search()) }
                )
                .focused($navFocusItem, equals: .search)
                .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.search, in: navPillNamespace, isSource: true))

                if viewModel.showShuffle {
                    ExpandableToolbarButton(
                        icon: "shuffle",
                        label: viewModel.isShuffling ? "..." : "Shuffle",
                        isAssetIcon: true,
                        action: { showShuffleDialog = true }
                    )
                    .focused($navFocusItem, equals: .shuffle)
                    .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.shuffle, in: navPillNamespace, isSource: true))
                }

                if viewModel.showFavorites {
                    ExpandableToolbarButton(
                        icon: "heart.fill",
                        label: "Favorites",
                        action: { router.navigatePrimary(to: .allFavorites) }
                    )
                    .focused($navFocusItem, equals: .favorites)
                    .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.favorites, in: navPillNamespace, isSource: true))
                }

                ExpandableToolbarButton(
                    icon: "folder.fill",
                    label: "Folders",
                    action: { router.navigatePrimary(to: .folderView) }
                )
                .focused($navFocusItem, equals: .folders)
                .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.folders, in: navPillNamespace, isSource: true))

                if viewModel.showGenres {
                    ExpandableToolbarButton(
                        icon: "theatermasks",
                        label: "Genres",
                        action: { router.navigatePrimary(to: .allGenres) }
                    )
                    .focused($navFocusItem, equals: .genres)
                    .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.genres, in: navPillNamespace, isSource: true))
                }

                if viewModel.showSeerrInToolbar {
                    ExpandableToolbarButton(
                        icon: viewModel.seerrIconName,
                        label: viewModel.seerrDisplayName,
                        isAssetIcon: true,
                        action: { router.navigatePrimary(to: .seerrDiscover) }
                    )
                    .focused($navFocusItem, equals: .seerr)
                    .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.seerr, in: navPillNamespace, isSource: true))
                }

                if viewModel.showLibraries && !viewModel.userViews.isEmpty {
                    ExpandableLibrariesButton(
                        libraries: viewModel.userViews,
                        activeLibraryId: nil,
                        onLibrarySelected: { library in
                            router.navigatePrimaryToLibrary(library)
                        },
                        pillNamespace: navPillNamespace,
                        pillAnchorId: .libraries,
                        pillHeight: navbarPillHeight,
                        onIconFocusChanged: { isIconFocused in
                            isLibrariesIconFocused = isIconFocused
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
                    .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.syncPlay, in: navPillNamespace, isSource: true))
                }

                ExpandableToolbarButton(
                    icon: "gearshape.fill",
                    label: "Settings",
                    action: { settingsRouter.open() }
                )
                .focused($navFocusItem, equals: .settings)
                .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.settings, in: navPillNamespace, isSource: true))
            }
            .disabled(lockToHomeOnEntry)
        }
        .background {
            ZStack {
                Capsule()
                    .fill(viewModel.overlayColor.opacity(viewModel.overlayOpacity))
                    .frame(height: navbarPillHeight)
                if let focused = navFocusItem, focused != .user {
                    if focused != .libraries || isLibrariesIconFocused {
                        Capsule()
                            .fill(theme.focusBorder.color)
                            .frame(height: navbarPillHeight)
                            .matchedGeometryEffect(id: focused, in: navPillNamespace, isSource: false)
                            .transition(.opacity)
                    }
                }
            }
        }
        .clipShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: navFocusItem)
    }
}

enum NavbarItem: Hashable {
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
            .frame(width: 52, height: 52)
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
                .font(.system(size: 24))
                .foregroundColor(theme.colorScheme.onButton)
        }
    }
}
