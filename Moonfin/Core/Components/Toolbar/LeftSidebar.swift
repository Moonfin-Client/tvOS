import SwiftUI

struct LeftSidebar: View {
    @StateObject private var viewModel: NavbarViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var settingsRouter: SettingsRouter

    @State private var isExpanded = false
    @State private var librariesFocused = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var librariesCollapseTask: Task<Void, Never>?

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: NavbarViewModel(container: container))
    }

    private static let collapsedWidth: CGFloat = 56
    private static let expandedWidth: CGFloat = 280

    var body: some View {
        HStack(spacing: 0) {
            sidebarContent
                .frame(width: isExpanded ? Self.expandedWidth : Self.collapsedWidth)
                .background(
                    isExpanded
                        ? LinearGradient(
                            colors: [
                                Color.black.opacity(0.9),
                                Color.black.opacity(0.7),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
                .clipped()
                .animation(.easeInOut(duration: 0.3), value: isExpanded)

            Spacer()
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.clockBehavior != .never {
                ToolbarClock()
                    .padding(.top, 24)
                    .padding(.trailing, 32)
            }
        }
    }

    private func handleSidebarFocus(_ focused: Bool) {
        collapseTask?.cancel()
        if focused {
            isExpanded = true
        } else {
            collapseTask = Task {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                isExpanded = false
            }
        }
    }

    private func handleLibraryFocus(_ focused: Bool) {
        librariesCollapseTask?.cancel()
        if focused {
            librariesFocused = true
        } else {
            librariesCollapseTask = Task {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                librariesFocused = false
            }
        }
    }

    // MARK: - Sidebar Content

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            userSection
                .padding(.top, 16)

            scrollableItems
                .padding(.vertical, SpaceTokens.spaceXs)

            settingsItem
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - User Section

    private var userSection: some View {
        SidebarIconItem(
            systemIcon: "person.fill",
            imageUrl: viewModel.userImageUrl,
            label: "User",
            isExpanded: isExpanded,
            onExpandedChange: handleSidebarFocus,
            action: {
                viewModel.switchUser()
                router.switchFlow(to: .startup)
            }
        )
    }

    // MARK: - Scrollable Nav Items

    private var scrollableItems: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                SidebarIconItem(
                    systemIcon: "house",
                    label: "Home",
                    isExpanded: isExpanded,
                    onExpandedChange: handleSidebarFocus,
                    action: { router.reset() }
                )

                SidebarIconItem(
                    systemIcon: "magnifyingglass",
                    label: "Search",
                    isExpanded: isExpanded,
                    onExpandedChange: handleSidebarFocus,
                    action: { router.navigate(to: .search()) }
                )

                SidebarIconItem(
                    assetIcon: "shuffle",
                    label: "Shuffle",
                    isExpanded: isExpanded,
                    onExpandedChange: handleSidebarFocus,
                    action: { /* TODO: shuffle action */ }
                )

                SidebarIconItem(
                    systemIcon: "heart.fill",
                    label: "Favorites",
                    isExpanded: isExpanded,
                    onExpandedChange: handleSidebarFocus,
                    action: { router.navigate(to: .allFavorites) }
                )

                SidebarIconItem(
                    systemIcon: "theatermasks",
                    label: "Genres",
                    isExpanded: isExpanded,
                    onExpandedChange: handleSidebarFocus,
                    action: { router.navigate(to: .allGenres) }
                )

                SidebarIconItem(
                    systemIcon: "folder.fill",
                    label: "Folders",
                    isExpanded: isExpanded,
                    onExpandedChange: handleSidebarFocus,
                    action: { router.navigate(to: .folderView) }
                )

                if !viewModel.userViews.isEmpty {
                    librariesSection
                }
            }
        }
    }

    // MARK: - Libraries Section

    private var librariesSection: some View {
        VStack(spacing: 2) {
            SidebarIconItem(
                systemIcon: "movieclapper.fill",
                label: "Libraries",
                isExpanded: isExpanded,
                onExpandedChange: handleSidebarFocus,
                onFocusChange: handleLibraryFocus,
                action: {
                    if let first = viewModel.userViews.first {
                        router.navigate(to: .libraryBrowser(itemId: first.id))
                    }
                }
            )

            if isExpanded && librariesFocused {
                ForEach(viewModel.userViews, id: \.id) { library in
                    SidebarTextItem(
                        label: library.name,
                        onFocusChange: { focused in
                            handleSidebarFocus(focused)
                            handleLibraryFocus(focused)
                        },
                        action: {
                            router.navigate(to: .libraryBrowser(itemId: library.id))
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: librariesFocused)
    }

    // MARK: - Settings

    private var settingsItem: some View {
        SidebarIconItem(
            systemIcon: "gearshape.fill",
            label: "Settings",
            isExpanded: isExpanded,
            onExpandedChange: handleSidebarFocus,
            action: { settingsRouter.open() }
        )
    }
}

// MARK: - SidebarIconItem

private struct SidebarIconItem: View {
    var systemIcon: String?
    var assetIcon: String?
    var imageUrl: String?
    let label: String
    let isExpanded: Bool
    let onExpandedChange: (Bool) -> Void
    var onFocusChange: ((Bool) -> Void)?
    let action: () -> Void

    init(systemIcon: String, imageUrl: String? = nil, label: String, isExpanded: Bool, onExpandedChange: @escaping (Bool) -> Void, onFocusChange: ((Bool) -> Void)? = nil, action: @escaping () -> Void) {
        self.init(systemIcon: systemIcon, assetIcon: nil, imageUrl: imageUrl, label: label, isExpanded: isExpanded, onExpandedChange: onExpandedChange, onFocusChange: onFocusChange, action: action)
    }

    init(assetIcon: String, label: String, isExpanded: Bool, onExpandedChange: @escaping (Bool) -> Void, onFocusChange: ((Bool) -> Void)? = nil, action: @escaping () -> Void) {
        self.init(systemIcon: nil, assetIcon: assetIcon, imageUrl: nil, label: label, isExpanded: isExpanded, onExpandedChange: onExpandedChange, onFocusChange: onFocusChange, action: action)
    }

    private init(systemIcon: String?, assetIcon: String?, imageUrl: String?, label: String, isExpanded: Bool, onExpandedChange: @escaping (Bool) -> Void, onFocusChange: ((Bool) -> Void)?, action: @escaping () -> Void) {
        self.systemIcon = systemIcon
        self.assetIcon = assetIcon
        self.imageUrl = imageUrl
        self.label = label
        self.isExpanded = isExpanded
        self.onExpandedChange = onExpandedChange
        self.onFocusChange = onFocusChange
        self.action = action
    }

    @FocusState private var isFocused: Bool
    @State private var delayedShowLabel = false
    @State private var labelTask: Task<Void, Never>?
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                iconContent
                    .frame(width: 32, height: 32)

                if delayedShowLabel {
                    HStack(spacing: 0) {
                        Spacer().frame(width: 12)
                        Text(label)
                            .font(.bodyMd)
                            .foregroundColor(.white)
                        Spacer().frame(width: 8)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: 2)
                    .padding(.horizontal, -4)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focusable()
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            onExpandedChange(focused)
            onFocusChange?(focused)
        }
        .onChange(of: isExpanded) { expanded in
            labelTask?.cancel()
            if expanded {
                labelTask = Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    delayedShowLabel = true
                }
            } else {
                delayedShowLabel = false
            }
        }
        .opacity(imageUrl != nil ? 1.0 : (isExpanded ? 1.0 : 0.5))
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .animation(.easeInOut(duration: 0.15), value: delayedShowLabel)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let imageUrl, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Image(systemName: systemIcon ?? "questionmark")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
            .clipShape(Circle())
        } else if let assetIcon {
            Image(assetIcon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(.white)
        } else {
            Image(systemName: systemIcon ?? "questionmark")
                .font(.system(size: 24))
                .foregroundColor(.white)
        }
    }
}

// MARK: - SidebarTextItem

private struct SidebarTextItem: View {
    let label: String
    var onFocusChange: ((Bool) -> Void)?
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Spacer().frame(width: 48)
                Text(label)
                    .font(.bodyMd)
                    .foregroundColor(.white)
                Spacer().frame(width: 8)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: 2)
                    .padding(.horizontal, -4)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focusable()
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            onFocusChange?(focused)
        }
    }
}
