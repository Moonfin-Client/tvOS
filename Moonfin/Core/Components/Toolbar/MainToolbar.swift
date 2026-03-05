import SwiftUI

struct MainToolbar: View {
    @StateObject private var viewModel: MainToolbarViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var settingsRouter: SettingsRouter

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: MainToolbarViewModel(container: container))
    }

    var body: some View {
        HStack(alignment: .center) {
            startSection
            Spacer()
            centerSection
            Spacer()
            endSection
        }
        .padding(.horizontal, 48)
        .padding(.top, 27)
        .padding(.bottom, 12)
        .frame(height: 95)
    }

    // MARK: - Start Section

    private var startSection: some View {
        UserAvatarToolbarButton(
            imageUrl: viewModel.userImageUrl,
            onTap: {
                viewModel.switchUser()
                router.switchFlow(to: .startup)
            }
        )
    }

    // MARK: - Center Section

    private var centerSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpaceTokens.spaceXs) {
                ExpandableToolbarButton(
                    icon: "house.fill",
                    label: "Home",
                    action: { router.reset() }
                )

                ExpandableToolbarButton(
                    icon: "magnifyingglass",
                    label: "Search",
                    action: { router.navigate(to: .search()) }
                )

                ExpandableToolbarButton(
                    icon: "heart.fill",
                    label: "Favorites",
                    action: { router.navigate(to: .allFavorites) }
                )

                ExpandableToolbarButton(
                    icon: "theatermasks.fill",
                    label: "Genres",
                    action: { router.navigate(to: .allGenres) }
                )

                ExpandableToolbarButton(
                    icon: "folder.fill",
                    label: "Folders",
                    action: { router.navigate(to: .folderView) }
                )

                if !viewModel.userViews.isEmpty {
                    ExpandableLibrariesButton(
                        libraries: viewModel.userViews,
                        activeLibraryId: nil,
                        onLibrarySelected: { library in
                            router.navigate(to: .libraryBrowser(itemId: library.id))
                        }
                    )
                }

                ExpandableToolbarButton(
                    icon: "gearshape.fill",
                    label: "Settings",
                    action: { settingsRouter.open() }
                )
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceXs)
            .background(
                Capsule()
                    .fill(theme.colorScheme.surface.opacity(0.6))
            )
        }
    }

    // MARK: - End Section

    private var endSection: some View {
        Group {
            if viewModel.clockBehavior != .never {
                ToolbarClock()
            }
        }
    }
}

// MARK: - User Avatar Button

private struct UserAvatarToolbarButton: View {
    let imageUrl: String?
    let onTap: () -> Void

    @FocusState private var isFocused: Bool
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
        .focusable()
        .focused($isFocused)
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
