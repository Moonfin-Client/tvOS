import SwiftUI

struct Navbar: View {
    @StateObject private var viewModel: NavbarViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var navFocusItem: NavbarItem?
    @State private var lockToHomeOnEntry = true
    @State private var relockTask: Task<Void, Never>?
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

            Group {
                ExpandableToolbarButton(
                    icon: "magnifyingglass",
                    label: "Search",
                    action: { router.navigatePrimary(to: .search()) }
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
                        action: { router.navigatePrimary(to: .allFavorites) }
                    )
                    .focused($navFocusItem, equals: .favorites)
                }

                ExpandableToolbarButton(
                    icon: "folder.fill",
                    label: "Folders",
                    action: { router.navigatePrimary(to: .folderView) }
                )
                .focused($navFocusItem, equals: .folders)

                if viewModel.showGenres {
                    ExpandableToolbarButton(
                        icon: "theatermasks",
                        label: "Genres",
                        action: { router.navigatePrimary(to: .allGenres) }
                    )
                    .focused($navFocusItem, equals: .genres)
                }

                if viewModel.showSeerrInToolbar {
                    ExpandableToolbarButton(
                        icon: viewModel.seerrIconName,
                        label: viewModel.seerrDisplayName,
                        isAssetIcon: true,
                        action: { router.navigatePrimary(to: .seerrDiscover) }
                    )
                    .focused($navFocusItem, equals: .seerr)
                }

                if viewModel.showLibraries && !viewModel.userViews.isEmpty {
                    ExpandableLibrariesButton(
                        libraries: viewModel.userViews,
                        activeLibraryId: nil,
                        onLibrarySelected: { library in
                            router.navigatePrimaryToLibrary(library)
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
            .disabled(lockToHomeOnEntry)
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
