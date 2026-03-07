import SwiftUI

private enum SidebarFocusItem: Hashable {
    case user, home, search, shuffle, favorites, genres, folders, libraries, settings
    case library(String)
}

struct LeftSidebar: View {
    @StateObject private var viewModel: NavbarViewModel
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var settingsRouter: SettingsRouter

    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>?
    @FocusState private var focusedItem: SidebarFocusItem?

    let mainNamespace: Namespace.ID
    @Environment(\.resetFocus) private var resetFocus

    static let sidebarInset: CGFloat = 90
    private static let expandedWidth: CGFloat = 280

    init(container: AppContainer, mainNamespace: Namespace.ID) {
        _viewModel = StateObject(wrappedValue: NavbarViewModel(container: container))
        self.mainNamespace = mainNamespace
    }

    private var isLibraryFocused: Bool {
        switch focusedItem {
        case .libraries, .library: return true
        default: return false
        }
    }

    var body: some View {
        sidebarColumn
            .ignoresSafeArea()
            .defaultFocus($focusedItem, .home)
            .onMoveCommand { direction in
                if direction == .right {
                    resetFocus(in: mainNamespace)
                }
            }
            .onChange(of: focusedItem) { newValue in
                collapseTask?.cancel()
                if newValue != nil {
                    isExpanded = true
                } else {
                    collapseTask = Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard !Task.isCancelled else { return }
                        isExpanded = false
                    }
                }
            }
    }

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            userSection
                .padding(.top, 16)

            scrollableItems
                .frame(maxHeight: .infinity, alignment: .center)

            settingsSection
                .padding(.bottom, 16)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(width: isExpanded ? Self.expandedWidth : Self.sidebarInset, alignment: .leading)
        .background(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.95),
                            Color.black.opacity(0.85),
                            Color.black.opacity(0.6),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: isExpanded ? Self.expandedWidth : 0)
                .animation(.easeInOut(duration: 0.25), value: isExpanded)
        }
        .clipped()
        .focusSection()
    }

    private var userSection: some View {
        SidebarIconItem(
            systemIcon: "person.fill",
            imageUrl: viewModel.userImageUrl,
            label: viewModel.userName.isEmpty ? "User" : viewModel.userName,
            isExpanded: isExpanded,
            isFocused: focusedItem == .user,
            action: {
                viewModel.switchUser()
                router.switchFlow(to: .startup)
            }
        )
        .focused($focusedItem, equals: .user)
    }

    private var sidebarItems: some View {
        VStack(spacing: 28) {
            SidebarIconItem(
                systemIcon: "house",
                label: "Home",
                isExpanded: isExpanded,
                isFocused: focusedItem == .home,
                action: { router.reset() }
            )
            .focused($focusedItem, equals: .home)

            SidebarIconItem(
                systemIcon: "magnifyingglass",
                label: "Search",
                isExpanded: isExpanded,
                isFocused: focusedItem == .search,
                action: { router.navigate(to: .search()) }
            )
            .focused($focusedItem, equals: .search)

            SidebarIconItem(
                assetIcon: "shuffle",
                label: "Shuffle",
                isExpanded: isExpanded,
                isFocused: focusedItem == .shuffle,
                action: { viewModel.performQuickShuffle(router: router) }
            )
            .focused($focusedItem, equals: .shuffle)
            .contextMenu {
                ForEach(ShuffleContentType.allCases, id: \.self) { type in
                    Button(type.displayName) {
                        viewModel.performShuffle(contentType: type, router: router)
                    }
                }
            }

            SidebarIconItem(
                systemIcon: "heart.fill",
                label: "Favorites",
                isExpanded: isExpanded,
                isFocused: focusedItem == .favorites,
                action: { router.navigate(to: .allFavorites) }
            )
            .focused($focusedItem, equals: .favorites)

            SidebarIconItem(
                systemIcon: "theatermasks",
                label: "Genres",
                isExpanded: isExpanded,
                isFocused: focusedItem == .genres,
                action: { router.navigate(to: .allGenres) }
            )
            .focused($focusedItem, equals: .genres)

            SidebarIconItem(
                systemIcon: "folder.fill",
                label: "Folders",
                isExpanded: isExpanded,
                isFocused: focusedItem == .folders,
                action: { router.navigate(to: .folderView) }
            )
            .focused($focusedItem, equals: .folders)

            SidebarIconItem(
                systemIcon: "movieclapper.fill",
                label: "Libraries",
                isExpanded: isExpanded,
                isFocused: focusedItem == .libraries,
                action: {
                    if let first = viewModel.userViews.first {
                        router.navigate(to: .libraryBrowser(itemId: first.id))
                    }
                }
            )
            .focused($focusedItem, equals: .libraries)
            .opacity(viewModel.userViews.isEmpty ? 0 : 1)
            .disabled(viewModel.userViews.isEmpty)

            if isExpanded && isLibraryFocused {
                ForEach(viewModel.userViews, id: \.id) { library in
                    SidebarTextItem(
                        label: library.name,
                        isFocused: focusedItem == .library(library.id),
                        action: {
                            router.navigate(to: .libraryBrowser(itemId: library.id))
                        }
                    )
                    .focused($focusedItem, equals: .library(library.id))
                }
            }
        }
    }

    private var settingsSection: some View {
        SidebarIconItem(
            systemIcon: "gearshape.fill",
            label: "Settings",
            isExpanded: isExpanded,
            isFocused: focusedItem == .settings,
            action: { settingsRouter.open() }
        )
        .focused($focusedItem, equals: .settings)
    }

    private var scrollableItems: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    sidebarItems
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
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

    @State private var delayedShowLabel = false
    @State private var labelTask: Task<Void, Never>?
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    iconContent
                        .frame(width: 32, height: 32)

                    if delayedShowLabel {
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
        .onChange(of: isExpanded) { expanded in
            labelTask?.cancel()
            if expanded {
                labelTask = Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        delayedShowLabel = true
                    }
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    delayedShowLabel = false
                }
            }
        }
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
