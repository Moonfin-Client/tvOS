import SwiftUI

private enum SidebarFocusItem: Hashable {
    case user, home, search, shuffle, favorites, genres, syncPlay, seerr, libraries, settings
    case library(String)
}

struct LeftSidebar: View {
    @StateObject private var viewModel: NavbarViewModel
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var sessionInitializer: SessionInitializer

    @State private var isExpanded = false
    @State private var isLibraryExpanded = false
    @State private var sidebarHadFocus = false
    @State private var allowAutoExpansion = false
    @State private var showShuffleDialog = false
    @State private var returnFocusItem: SidebarFocusItem = .home
    @FocusState private var focusedItem: SidebarFocusItem?

    let onMoveToContent: (() -> Void)?
    let onSidebarEntered: (() -> Void)?

    static let sidebarInset: CGFloat = 90
    private static let expandedWidth: CGFloat = 560

    init(
        container: AppContainer,
        onMoveToContent: (() -> Void)? = nil,
        onSidebarEntered: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: NavbarViewModel(container: container))
        self.onMoveToContent = onMoveToContent
        self.onSidebarEntered = onSidebarEntered
    }

    private var hasVisibleLibraries: Bool {
        viewModel.showLibraries && !viewModel.userViews.isEmpty
    }

    private func normalizedFocusItem(_ item: SidebarFocusItem) -> SidebarFocusItem {
        switch item {
        case .shuffle:
            return viewModel.showShuffle ? item : .home
        case .favorites:
            return viewModel.showFavorites ? item : .home
        case .genres:
            return viewModel.showGenres ? item : .home
        case .syncPlay:
            return viewModel.showSyncPlay ? item : .home
        case .seerr:
            return viewModel.showSeerrInNavigation ? item : .home
        case .libraries:
            return hasVisibleLibraries ? item : .home
        case .library(let id):
            guard hasVisibleLibraries,
                  viewModel.userViews.contains(where: { $0.id == id }) else { return .home }
            return item
        default:
            return item
        }
    }

    private func applyExpansionState(for item: SidebarFocusItem?) {
        guard let item else { return }
        isExpanded = true
        if case .library = item {
            isLibraryExpanded = true
        } else if item != .libraries {
            isLibraryExpanded = false
        }
    }

    private func routeHomeAndHandoffFocus() {
        router.reset()
        returnFocusItem = .home
        onMoveToContent?()
    }

    private func handoffFocusToContent() {
        if let current = focusedItem {
            returnFocusItem = current
        }
        onMoveToContent?()
    }

    var body: some View {
        sidebarColumn
            .ignoresSafeArea()
            .onAppear {
                sidebarHadFocus = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    allowAutoExpansion = true
                }
            }
            .onMoveCommand { direction in
                if direction == .right {
                    handoffFocusToContent()
                }
            }
            .onChange(of: focusedItem) { newValue in
                if let newValue {
                    if allowAutoExpansion {
                        applyExpansionState(for: newValue)
                    }
                    if !sidebarHadFocus {
                        sidebarHadFocus = true
                        onSidebarEntered?()
                        let target = normalizedFocusItem(returnFocusItem)
                        if newValue != target {
                            if allowAutoExpansion {
                                applyExpansionState(for: target)
                            }
                            DispatchQueue.main.async {
                                focusedItem = target
                            }
                            return
                        }
                    }
                    returnFocusItem = newValue
                } else {
                    sidebarHadFocus = false
                    isExpanded = false
                    isLibraryExpanded = false
                }
            }
            .sheet(isPresented: $showShuffleDialog) {
                ShuffleOptionsDialog(
                    libraries: viewModel.userViews,
                    onQuickShuffle: {
                        showShuffleDialog = false
                        viewModel.performShuffle(router: router)
                        handoffFocusToContent()
                    },
                    onLibraryShuffle: { libraryId in
                        showShuffleDialog = false
                        viewModel.performShuffle(libraryId: libraryId, router: router)
                        handoffFocusToContent()
                    },
                    onGenreShuffle: { genreName in
                        showShuffleDialog = false
                        viewModel.performShuffle(genreName: genreName, router: router)
                        handoffFocusToContent()
                    },
                    onDismiss: { showShuffleDialog = false },
                    fetchGenres: { await viewModel.fetchGenres() }
                )
            }
    }

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            userSection
                .padding(.top, 16)

            scrollableItems
                .frame(maxHeight: .infinity, alignment: .center)

            if !isExpanded {
                settingsSection
                    .padding(.bottom, 16)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(width: isExpanded ? Self.expandedWidth : Self.sidebarInset, alignment: .leading)
        .background(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            viewModel.overlayColor.opacity(viewModel.overlayOpacity * 1.9),
                            viewModel.overlayColor.opacity(viewModel.overlayOpacity * 1.7),
                            viewModel.overlayColor.opacity(viewModel.overlayOpacity * 1.2),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: isExpanded ? Self.expandedWidth : 0)
        }
        .clipped()
        .animation(.easeOut(duration: 0.18), value: isExpanded)

    }

    private var userSection: some View {
        SidebarIconItem(
            systemIcon: "person.fill",
            imageUrl: viewModel.userImageUrl,
            label: viewModel.userName.isEmpty ? "User" : viewModel.userName,
            isExpanded: isExpanded,
            isFocused: focusedItem == .user,
            action: {
                let serverId = viewModel.switchUser()
                sessionInitializer.suppressAutoLogin = true
                sessionInitializer.restoredServerId = serverId
                router.switchFlow(to: .startup)
            }
        )
        .focused($focusedItem, equals: .user)
    }

    private var sidebarItems: some View {
        VStack(spacing: 28) {
            SidebarIconItem(
                systemIcon: "house",
                label: Strings.home,
                isExpanded: isExpanded,
                isFocused: focusedItem == .home,
                action: { routeHomeAndHandoffFocus() }
            )
            .focused($focusedItem, equals: .home)

            SidebarIconItem(
                systemIcon: "magnifyingglass",
                label: Strings.search,
                isExpanded: isExpanded,
                isFocused: focusedItem == .search,
                action: {
                    router.navigatePrimary(to: .search())
                    handoffFocusToContent()
                }
            )
            .focused($focusedItem, equals: .search)

            if viewModel.showShuffle {
                SidebarIconItem(
                    assetIcon: "shuffle",
                    label: viewModel.isShuffling ? "..." : Strings.shuffle,
                    isExpanded: isExpanded,
                    isFocused: focusedItem == .shuffle,
                    action: { showShuffleDialog = true }
                )
                .focused($focusedItem, equals: .shuffle)
            }

            if viewModel.showFavorites {
                SidebarIconItem(
                    systemIcon: "heart.fill",
                    label: Strings.favorites,
                    isExpanded: isExpanded,
                    isFocused: focusedItem == .favorites,
                    action: {
                        router.navigatePrimary(to: .allFavorites)
                        handoffFocusToContent()
                    }
                )
                .focused($focusedItem, equals: .favorites)
            }

            if viewModel.showGenres {
                SidebarIconItem(
                    systemIcon: "theatermasks",
                    label: Strings.genres,
                    isExpanded: isExpanded,
                    isFocused: focusedItem == .genres,
                    action: {
                        router.navigatePrimary(to: .allGenres)
                        handoffFocusToContent()
                    }
                )
                .focused($focusedItem, equals: .genres)
            }

            if viewModel.showSyncPlay {
                SidebarIconItem(
                    systemIcon: "person.3.fill",
                    label: Strings.syncPlay,
                    isExpanded: isExpanded,
                    isFocused: focusedItem == .syncPlay,
                    action: {
                        settingsRouter.open(to: .syncPlay)
                        handoffFocusToContent()
                    }
                )
                .focused($focusedItem, equals: .syncPlay)
            }

            if viewModel.showSeerrInNavigation {
                SidebarIconItem(
                    assetIcon: viewModel.seerrIconName,
                    label: viewModel.seerrDisplayName,
                    isExpanded: isExpanded,
                    isFocused: focusedItem == .seerr,
                    action: {
                        router.navigatePrimary(to: .seerrDiscover)
                        handoffFocusToContent()
                    }
                )
                .focused($focusedItem, equals: .seerr)
            }

            if viewModel.showLibraries {
                SidebarIconItem(
                    systemIcon: "movieclapper.fill",
                    label: Strings.libraries,
                    isExpanded: isExpanded,
                    isFocused: focusedItem == .libraries,
                    action: { isLibraryExpanded.toggle() }
                )
                .focused($focusedItem, equals: .libraries)
                .opacity(viewModel.userViews.isEmpty ? 0 : 1)
                .disabled(viewModel.userViews.isEmpty)
            }

            if isExpanded && isLibraryExpanded {
                ForEach(viewModel.userViews, id: \.id) { library in
                    SidebarTextItem(
                        label: library.name,
                        isFocused: focusedItem == .library(library.id),
                        action: {
                            router.navigatePrimaryToLibrary(library)
                            handoffFocusToContent()
                        }
                    )
                    .focused($focusedItem, equals: .library(library.id))
                }
            }

            if isExpanded {
                SidebarIconItem(
                    systemIcon: "gearshape.fill",
                    label: Strings.settings,
                    isExpanded: isExpanded,
                    isFocused: focusedItem == .settings,
                    action: { settingsRouter.open() }
                )
                .focused($focusedItem, equals: .settings)
            }
        }
    }

    private var settingsSection: some View {
        SidebarIconItem(
            systemIcon: "gearshape.fill",
            label: Strings.settings,
            isExpanded: isExpanded,
            isFocused: focusedItem == .settings,
            action: { settingsRouter.open() }
        )
        .focused($focusedItem, equals: .settings)
    }

    private var scrollableItems: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                sidebarItems
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
                    .frame(minHeight: geo.size.height)
            }
            .scrollDisabled(!isExpanded)
        }
    }
}

private struct SidebarIconItem: View {
    let systemIcon: String?
    let assetIcon: String?
    let imageUrl: String?
    let label: String
    let isExpanded: Bool
    let isFocused: Bool
    let action: () -> Void

    init(systemIcon: String, imageUrl: String? = nil, label: String, isExpanded: Bool, isFocused: Bool, action: @escaping () -> Void) {
        self.systemIcon = systemIcon
        self.assetIcon = nil
        self.imageUrl = imageUrl
        self.label = label
        self.isExpanded = isExpanded
        self.isFocused = isFocused
        self.action = action
    }

    init(assetIcon: String, label: String, isExpanded: Bool, isFocused: Bool, action: @escaping () -> Void) {
        self.systemIcon = nil
        self.assetIcon = assetIcon
        self.imageUrl = nil
        self.label = label
        self.isExpanded = isExpanded
        self.isFocused = isFocused
        self.action = action
    }

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    iconContent
                        .frame(width: 32, height: 32)

                    if isExpanded {
                        Text(label)
                            .font(.bodyMd)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: 2)
                )

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(CleanButtonStyle())
        .opacity(imageUrl != nil ? 1.0 : (isExpanded ? 1.0 : 0.5))
    }

    @ViewBuilder
    private var iconContent: some View {
        if let imageUrl, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    defaultPersonIconOrSystemIcon
                }
            }
            .clipShape(Circle())
        } else if let assetIcon {
            Image(assetIcon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
        } else {
            defaultPersonIconOrSystemIcon
        }
    }

    @ViewBuilder
    private var defaultPersonIconOrSystemIcon: some View {
        if systemIcon == "person.fill" {
            PersonAvatarShape()
                .fill(.white)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: systemIcon ?? "questionmark")
                .font(.system(size: 24))
                .foregroundColor(.white)
        }
    }
}

private struct SidebarTextItem: View {
    let label: String
    let isFocused: Bool
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Spacer().frame(width: 56)

                Text(label)
                    .font(.bodyMd)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: 2)
                    )

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(CleanButtonStyle())
    }
}
