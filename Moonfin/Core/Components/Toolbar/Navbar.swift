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
    @State private var showAccountSwitcherDialog = false
    @State private var accountSwitcherBusy = false
    @State private var accountSwitcherAccounts: [AccountSwitcherAccount] = []
    private let navbarPillHeight: CGFloat = 64
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

    private func presentAccountSwitcher() {
        accountSwitcherAccounts = viewModel.accountSwitcherAccounts()
        accountSwitcherBusy = false
        showAccountSwitcherDialog = true
    }

    private func navigateToStartup(restoredServerId: UUID?, restoredUserId: UUID? = nil, suppressAutoLogin: Bool) {
        sessionInitializer.endSwitchUserTransition()
        sessionInitializer.suppressAutoLogin = suppressAutoLogin
        sessionInitializer.restoredServerId = restoredServerId
        sessionInitializer.restoredUserId = restoredUserId
        router.switchFlow(to: .startup)
    }

    private func handleAccountSelection(_ account: AccountSwitcherAccount) {
        if account.isActive {
            showAccountSwitcherDialog = false
            return
        }

        accountSwitcherBusy = true
        accountSwitcherBusy = false
        showAccountSwitcherDialog = false
        sessionInitializer.beginSwitchUserTransition()
        sessionInitializer.suppressAutoLogin = false
        sessionInitializer.restoredUserId = account.user.id
        sessionInitializer.restoredServerId = nil
        router.switchFlow(to: .startup)
        router.navigate(to: .serverUsers(serverId: account.server.id))
    }

    private func handleSignOutCurrent() {
        accountSwitcherBusy = true
        viewModel.signOutCurrentSession()
        accountSwitcherBusy = false
        showAccountSwitcherDialog = false
        navigateToStartup(restoredServerId: nil, suppressAutoLogin: true)
    }

    private func handleSignOutAllUsers() {
        accountSwitcherBusy = true
        viewModel.signOutAllStoredAccounts()
        accountSwitcherBusy = false
        showAccountSwitcherDialog = false
        navigateToStartup(restoredServerId: nil, suppressAutoLogin: true)
    }

    private func handleSelectServer() {
        showAccountSwitcherDialog = false
        navigateToStartup(restoredServerId: nil, suppressAutoLogin: true)
    }

    private func handleAddUser() {
        showAccountSwitcherDialog = false
        navigateToStartup(restoredServerId: viewModel.currentServerId, suppressAutoLogin: true)
    }

    private var visibleCenterItems: [NavbarItem] {
        var items: [NavbarItem] = [.home, .search]
        if viewModel.showShuffle { items.append(.shuffle) }
        if viewModel.showFavorites { items.append(.favorites) }
        if viewModel.showGenres { items.append(.genres) }
        if viewModel.showSeerrInToolbar { items.append(.seerr) }
        if viewModel.showLibraries && !viewModel.userViews.isEmpty { items.append(.libraries) }
        if viewModel.showSyncPlay { items.append(.syncPlay) }
        items.append(.settings)
        return items
    }

    private func navCycleIndex(for item: NavbarItem) -> Int? {
        visibleCenterItems.firstIndex(of: item)
    }

    var body: some View {
        ZStack {
            HStack {
                startSection
                Spacer()
            }
            centerSection
        }
        .padding(.leading, 36)
        .padding(.trailing, 56)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(height: 128)
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
        .fullScreenCover(isPresented: $showShuffleDialog) {
            ShuffleOptionsDialog(
                libraries: viewModel.shuffleLibraries,
                onSelectItem: { item in
                    showShuffleDialog = false
                    router.navigatePrimaryToItem(item)
                    onMoveToContent?()
                },
                onDismiss: { showShuffleDialog = false },
                fetchGenres: { libraryId in await viewModel.fetchGenres(libraryId: libraryId) },
                fetchPreviewItems: { libraryId, genreName in
                    await viewModel.fetchShufflePreviewItems(libraryId: libraryId, genreName: genreName)
                },
                fetchRatings: { item in
                    await viewModel.fetchShuffleRatings(for: item)
                },
                posterUrlForItem: { item in
                    viewModel.shufflePosterUrl(for: item)
                },
                enableAdditionalRatings: viewModel.enableAdditionalRatings
            )
        }
        .fullScreenCover(isPresented: $showAccountSwitcherDialog) {
            AccountSwitcherDialog(
                accounts: accountSwitcherAccounts,
                isBusy: accountSwitcherBusy,
                onSelectAccount: handleAccountSelection,
                onAddUser: handleAddUser,
                onSelectServer: handleSelectServer,
                onSignOutCurrent: handleSignOutCurrent,
                onSignOutAllUsers: handleSignOutAllUsers,
                onDismiss: { showAccountSwitcherDialog = false }
            )
        }
        .onChange(of: showAccountSwitcherDialog) { showing in
            if showing {
                viewModel.addScreensaverLock()
            } else {
                viewModel.removeScreensaverLock()
            }
        }
    }

    private var startSection: some View {
        UserAvatarToolbarButton(
            imageUrl: viewModel.userImageUrl,
            userName: viewModel.userName,
            isFocused: navFocusItem == .user,
            onTap: { presentAccountSwitcher() }
        )
        .disabled(lockToHomeOnEntry)
        .focused($navFocusItem, equals: .user)
    }

    private var centerSection: some View {
        HStack(spacing: 6) {
            ExpandableToolbarButton(
                icon: "house",
                label: Strings.home,
                cycleIndex: navCycleIndex(for: .home),
                action: { routeHomeAndHandoffFocus() }
            )
            .focused($navFocusItem, equals: .home)
            .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.home, in: navPillNamespace, isSource: true))

            Group {
                ExpandableToolbarButton(
                    icon: "magnifyingglass",
                    label: Strings.search,
                    cycleIndex: navCycleIndex(for: .search),
                    action: { router.navigatePrimary(to: .search()) }
                )
                .focused($navFocusItem, equals: .search)
                .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.search, in: navPillNamespace, isSource: true))

                if viewModel.showShuffle {
                    ExpandableToolbarButton(
                        icon: "shuffle",
                        label: viewModel.isShuffling ? "..." : Strings.shuffle,
                        isAssetIcon: true,
                        cycleIndex: navCycleIndex(for: .shuffle),
                        action: { showShuffleDialog = true }
                    )
                    .focused($navFocusItem, equals: .shuffle)
                    .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.shuffle, in: navPillNamespace, isSource: true))
                }

                if viewModel.showFavorites {
                    ExpandableToolbarButton(
                        icon: "heart.fill",
                        label: Strings.favorites,
                        cycleIndex: navCycleIndex(for: .favorites),
                        action: { router.navigatePrimary(to: .allFavorites) }
                    )
                    .focused($navFocusItem, equals: .favorites)
                    .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.favorites, in: navPillNamespace, isSource: true))
                }

                if viewModel.showGenres {
                    ExpandableToolbarButton(
                        icon: "theatermasks",
                        label: Strings.genres,
                        cycleIndex: navCycleIndex(for: .genres),
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
                        cycleIndex: navCycleIndex(for: .seerr),
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
                        cycleIndex: navCycleIndex(for: .libraries),
                        onIconFocusChanged: { isIconFocused in
                            isLibrariesIconFocused = isIconFocused
                        }
                    )
                    .focused($navFocusItem, equals: .libraries)
                }

                if viewModel.showSyncPlay {
                    ExpandableToolbarButton(
                        icon: "person.3.fill",
                        label: Strings.syncPlay,
                        cycleIndex: navCycleIndex(for: .syncPlay),
                        action: { settingsRouter.open(to: .syncPlay) }
                    )
                    .focused($navFocusItem, equals: .syncPlay)
                    .background(Color.clear.frame(height: navbarPillHeight).matchedGeometryEffect(id: NavbarItem.syncPlay, in: navPillNamespace, isSource: true))
                }

                ExpandableToolbarButton(
                    icon: "gearshape.fill",
                    label: Strings.settings,
                    cycleIndex: navCycleIndex(for: .settings),
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
                if let navBorder = theme.activeSpec.borders.navBorder {
                    Capsule()
                        .stroke(navBorder.color.color, lineWidth: navBorder.width)
                        .frame(height: navbarPillHeight)
                }
                if let focused = navFocusItem, focused != .user {
                    if focused != .libraries || isLibrariesIconFocused {
                        Group {
                            if theme.isNeonPulseTheme {
                                Capsule()
                                    .stroke(theme.effectiveFocusColor, lineWidth: 2.5)
                            } else {
                                Capsule()
                                    .fill(theme.effectiveFocusColor)
                            }
                        }
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
    case seerr
    case libraries
    case syncPlay
    case settings
}

private struct UserAvatarToolbarButton: View {
    let imageUrl: String?
    let userName: String
    let isFocused: Bool
    let onTap: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
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
                        .stroke(isFocused ? theme.effectiveFocusColor : .clear, lineWidth: isFocused ? 3 : 0)
                )

                if isFocused {
                    Text(userName.isEmpty ? "User" : userName)
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.onBackground)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
        }
        .buttonStyle(CleanButtonStyle())
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    private var fallbackIcon: some View {
        ZStack {
            Circle()
                .fill(theme.colorScheme.button)
            PersonAvatarShape()
                .fill(theme.colorScheme.onButton)
                .frame(width: 26, height: 26)
        }
    }
}

private enum AccountSwitcherFocusTarget: Hashable {
    case account(String)
    case addUser
    case selectServer
    case signOut
    case signOutAll
}

struct AccountSwitcherDialog: View {
    let accounts: [AccountSwitcherAccount]
    let isBusy: Bool
    let onSelectAccount: (AccountSwitcherAccount) -> Void
    let onAddUser: () -> Void
    let onSelectServer: () -> Void
    let onSignOutCurrent: () -> Void
    let onSignOutAllUsers: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var theme: MoonfinTheme
    @FocusState private var focusedTarget: AccountSwitcherFocusTarget?

    private let cardWidth: CGFloat = 176
    private let cardHeight: CGFloat = 296
    private let avatarSize: CGFloat = 150

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
                Text(Strings.switchUser)
                    .font(.titleLg)
                    .foregroundColor(theme.colorScheme.onBackground)

                Divider()
                    .background(theme.colorScheme.onBackground.opacity(0.08))

                accountRow
                    .padding(.bottom, SpaceTokens.spaceXl)

                if accounts.isEmpty {
                    Text(Strings.noStoredAccounts)
                        .font(.bodySm)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack(spacing: SpaceTokens.spaceSm) {
                        AccountSwitcherActionButton(
                            title: Strings.selectServer,
                            isFocused: focusedTarget == .selectServer,
                            isDestructive: false,
                            action: onSelectServer
                        )
                        .focused($focusedTarget, equals: .selectServer)
                        .disabled(isBusy)

                        AccountSwitcherActionButton(
                            title: Strings.signOut,
                            isFocused: focusedTarget == .signOut,
                            isDestructive: false,
                            action: onSignOutCurrent
                        )
                        .focused($focusedTarget, equals: .signOut)
                        .disabled(isBusy)
                    }
                    .focusSection()
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                if accounts.count > 1 {
                    HStack {
                        Spacer(minLength: 0)
                        AccountSwitcherActionButton(
                            title: Strings.signOutAllUsers,
                            isFocused: focusedTarget == .signOutAll,
                            isDestructive: true,
                            action: onSignOutAllUsers
                        )
                        .focused($focusedTarget, equals: .signOutAll)
                        .disabled(isBusy)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 30)
            .frame(maxWidth: 1120, minHeight: 720)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.extraLarge)
                    .fill(theme.colorScheme.surface.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.extraLarge)
                            .stroke(theme.colorScheme.onBackground.opacity(0.18), lineWidth: 1.5)
                    )
            )
            .padding(.horizontal, 52)
            .padding(.vertical, 34)

            if isBusy {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                ProgressView()
                    .tint(theme.colorScheme.onBackground)
                    .scaleEffect(1.3)
            }
        }
        .focusSection()
        .onAppear {
            if focusedTarget == nil {
                focusedTarget = initialFocusTarget
            }
        }
        .onChange(of: accounts.map(\.id)) { _ in
            if focusedTarget == nil || !isFocusedTargetStillValid {
                focusedTarget = initialFocusTarget
            }
        }
        .onExitCommand {
            guard !isBusy else { return }
            onDismiss()
        }
    }

    private var accountRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpaceTokens.spaceLg) {
                ForEach(accounts) { account in
                    AccountSwitcherCardView(
                        account: account,
                        isFocused: focusedTarget == .account(account.id),
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        avatarSize: avatarSize,
                        action: { onSelectAccount(account) }
                    )
                    .focused($focusedTarget, equals: .account(account.id))
                    .disabled(isBusy)
                }

                AccountSwitcherAddUserCard(
                    isFocused: focusedTarget == .addUser,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    avatarSize: avatarSize,
                    action: onAddUser
                )
                .focused($focusedTarget, equals: .addUser)
                .disabled(isBusy)
            }
            .padding(.horizontal, SpaceTokens.spaceXs)
            .padding(.vertical, SpaceTokens.spaceSm)
            .frame(maxWidth: .infinity, alignment: accounts.isEmpty ? .center : .leading)
        }
        .frame(height: cardHeight + 22)
        .focusSection()
    }

    private var initialFocusTarget: AccountSwitcherFocusTarget {
        if let active = accounts.first(where: { $0.isActive }) {
            return .account(active.id)
        }
        if let first = accounts.first {
            return .account(first.id)
        }
        return .addUser
    }

    private var isFocusedTargetStillValid: Bool {
        guard let focusedTarget else { return false }
        switch focusedTarget {
        case .account(let id):
            return accounts.contains(where: { $0.id == id })
        case .addUser:
            return true
        case .selectServer, .signOut:
            return !accounts.isEmpty
        case .signOutAll:
            return accounts.count > 1
        }
    }
}

private struct AccountSwitcherCardView: View {
    let account: AccountSwitcherAccount
    let isFocused: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let avatarSize: CGFloat
    let action: () -> Void

    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpaceTokens.spaceSm) {
                avatar

                Text(account.user.name)
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(account.server.name)
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                ZStack {
                    if account.isActive {
                        Text(Strings.accountActiveBadge)
                            .font(.captionXs)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.horizontal, SpaceTokens.spaceSm)
                            .padding(.vertical, SpaceTokens.space2xs)
                            .background(
                                Capsule()
                                    .fill(theme.effectiveFocusColor)
                            )
                    }
                }
                .frame(height: 24)
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceSm)
            .frame(width: cardWidth, height: cardHeight)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(theme.colorScheme.surface.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.medium)
                            .stroke(
                                isFocused ? theme.effectiveFocusColor : theme.colorScheme.onBackground.opacity(0.12),
                                lineWidth: isFocused ? 2.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(CleanButtonStyle())
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(theme.colorScheme.surface.opacity(0.5))

            if let imageUrl = account.imageUrl,
               let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    isFocused ? theme.effectiveFocusColor : theme.colorScheme.onBackground.opacity(0.18),
                    lineWidth: isFocused ? 3 : 1
                )
        )
    }

    private var fallbackAvatar: some View {
        PersonAvatarShape()
            .fill(theme.colorScheme.onBackground.opacity(0.7))
            .frame(width: 68, height: 68)
    }
}

private struct AccountSwitcherAddUserCard: View {
    let isFocused: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let avatarSize: CGFloat
    let action: () -> Void

    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpaceTokens.spaceMd) {
                ZStack {
                    Circle()
                        .fill(theme.colorScheme.surface.opacity(0.5))
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 58, weight: .medium))
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.9))
                }
                .frame(width: avatarSize, height: avatarSize)
                .overlay(
                    Circle()
                        .stroke(
                            isFocused ? theme.effectiveFocusColor : theme.colorScheme.onBackground.opacity(0.18),
                            lineWidth: isFocused ? 3 : 1
                        )
                )

                Text(Strings.addUser)
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceSm)
            .frame(width: cardWidth, height: cardHeight)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(theme.colorScheme.surface.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.medium)
                            .stroke(
                                isFocused ? theme.effectiveFocusColor : theme.colorScheme.onBackground.opacity(0.12),
                                lineWidth: isFocused ? 2.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(CleanButtonStyle())
    }
}

private struct AccountSwitcherActionButton: View {
    let title: String
    let isFocused: Bool
    let isDestructive: Bool
    let action: () -> Void

    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bodyMd)
                .fontWeight(.medium)
                .foregroundColor(titleColor)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.vertical, SpaceTokens.spaceSm)
                .background(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(CleanButtonStyle())
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isFocused)
    }

    private var titleColor: Color {
        if isFocused {
            return .black
        }
        return theme.colorScheme.onBackground
    }

    private var backgroundColor: Color {
        if isFocused {
            return isDestructive ? Color(red: 0.85, green: 0.2, blue: 0.2) : Color.white
        }
        if isDestructive {
            return Color(red: 0.78, green: 0.16, blue: 0.16).opacity(0.85)
        }
        return Color.white.opacity(0.1)
    }
}
