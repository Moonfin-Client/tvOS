import SwiftUI
import Nuke

struct LibraryBrowseScreen: View {
    @StateObject private var viewModel: LibraryBrowseViewModel
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @State private var showSortDialog = false
    @State private var showSettings = false
    @StateObject private var ratingsViewModel: MediaBarRatingsViewModel

    init(container: AppContainer, parentId: String, serverId: String? = nil,
         includeTypes: [ItemType]? = nil, genreName: String? = nil) {
        _viewModel = StateObject(wrappedValue: LibraryBrowseViewModel(
            container: container, parentId: parentId, serverId: serverId,
            includeTypes: includeTypes, genreName: genreName
        ))
        _ratingsViewModel = StateObject(wrappedValue: MediaBarRatingsViewModel(
            mdbListRepository: container.mdbListRepository,
            userPreferences: container.userPreferences
        ))
    }

    var body: some View {
        ZStack {
            backdropLayer
            overlayLayer

            VStack(spacing: 0) {
                libraryHeader
                    .padding(.horizontal, 60)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                if viewModel.isLoading && viewModel.items.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                } else if viewModel.items.isEmpty {
                    Spacer()
                    Text("No items found")
                        .font(.bodyLg)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                } else {
                    libraryGrid
                }

                statusBar
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.initialize()
            router.hideNavbar = true
        }
        .sheet(isPresented: $showSortDialog) {
            FilterSortDialogView(
                sortOptions: viewModel.sortOptions,
                currentSort: viewModel.currentSort,
                filterFavorites: viewModel.filterFavorites,
                filterUnwatched: viewModel.filterUnwatched,
                showUnwatchedToggle: viewModel.collectionType == "movies" || viewModel.collectionType == "tvshows",
                onSortSelected: { viewModel.setSortOption($0) },
                onToggleFavorites: { viewModel.toggleFavorites() },
                onToggleUnwatched: { viewModel.toggleUnwatched() },
                onDismiss: { showSortDialog = false }
            )
        }
        .sheet(isPresented: $showSettings) {
            DisplaySettingsDialogView(
                posterSize: viewModel.posterSize,
                imageType: viewModel.imageType,
                onPosterSizeChanged: { viewModel.setPosterSize($0) },
                onImageTypeChanged: { viewModel.setImageType($0) }
            )
        }
    }

    // MARK: - Header

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    Text(viewModel.libraryName)
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.white)

                    if viewModel.totalItems > 0 {
                        Text("\(viewModel.totalItems) Items")
                            .font(.captionXs)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                Spacer()
            }

            focusedItemHud

            HStack {
                toolbarButtons
                Spacer()
                if viewModel.currentSort.sortBy == .sortName {
                    alphaPickerBar
                }
            }
        }
    }

    private var focusedItemHud: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let item = viewModel.focusedItem {
                Text(item.name)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                SimpleInfoRow(item: item)

                MediaBarRatingsRow(
                    ratings: ratingsViewModel.ratings,
                    enableAdditionalRatings: ratingsViewModel.enableAdditionalRatings
                )
            }
        }
        .frame(height: 110, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: viewModel.focusedItem?.id) { _ in
            if let item = viewModel.focusedItem {
                ratingsViewModel.loadRatings(for: item)
            }
        }
    }

    private var toolbarButtons: some View {
        HStack(spacing: 4) {
            ToolbarIconButton(
                systemImage: "house",
                isActive: false,
                theme: theme,
                action: { router.navigate(to: .home) }
            )

            ToolbarIconButton(
                systemImage: "arrow.up.arrow.down",
                isActive: viewModel.filterFavorites || viewModel.filterUnwatched,
                theme: theme,
                action: { showSortDialog = true }
            )

            if !viewModel.isForcedSquareMode {
                ToolbarIconButton(
                    systemImage: "gearshape",
                    isActive: false,
                    theme: theme,
                    action: { showSettings = true }
                )
            }
        }
    }

    private var alphaPickerBar: some View {
        let letters = ["#"] + (65...90).map { String(UnicodeScalar($0)) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    AlphaPickerLetter(
                        letter: letter,
                        isSelected: letter == "#" ? viewModel.startLetter == nil : viewModel.startLetter == letter,
                        theme: theme,
                        action: { viewModel.setStartLetter(letter == "#" ? nil : letter) }
                    )
                }
            }
        }
    }

    // MARK: - Grid

    private var libraryGrid: some View {
        let dims = viewModel.cardDimensions
        let columns = [GridItem(.adaptive(minimum: dims.width + 32), spacing: 16)]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    LibraryPosterCard(
                        item: item,
                        imageUrl: viewModel.imageUrl(for: item),
                        cardWidth: dims.width,
                        cardHeight: dims.height,
                        metadata: viewModel.buildMetadata(for: item),
                        watchedIndicator: container.userPreferences[UserPreferences.watchedIndicator],
                        showLabels: true,
                        onFocused: { viewModel.setFocusedItem($0) },
                        onTap: { navigateToItem(item) }
                    )
                    .onAppear {
                        if index >= viewModel.items.count - 10 { viewModel.loadMore() }
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text(viewModel.buildStatusText())
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))

            Spacer()

            Text("\(viewModel.items.count) | \(viewModel.totalItems)")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 4)
    }

    // MARK: - Background

    private var backdropLayer: some View {
        GeometryReader { geo in
            if viewModel.backgroundService.enabled,
               let urlString = viewModel.backgroundService.currentBackdropUrl,
               let url = URL(string: urlString) {
                CachedImage(
                    url: url,
                    processors: [
                        ImageProcessors.Resize(size: CGSize(width: geo.size.width, height: geo.size.height), contentMode: .aspectFill),
                        ImageProcessors.GaussianBlur(radius: Int(viewModel.backgroundService.blurAmount))
                    ]
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .drawingGroup()
                .transition(.opacity)
                .id(urlString)
            }
        }
        .animation(.easeInOut(duration: BackgroundService.transitionDuration), value: viewModel.backgroundService.currentBackdropUrl)
        .background(theme.colorScheme.background)
    }

    private var overlayLayer: some View {
        let hasBackdrop = viewModel.backgroundService.currentBackdropUrl != nil
        let alpha = hasBackdrop ? 0.45 : 0.75
        return Color(red: 0.063, green: 0.082, blue: 0.157)
            .opacity(alpha)
            .ignoresSafeArea()
    }

    private func navigateToItem(_ item: ServerItem) {
        switch item.type {
        case .userView, .collectionFolder:
            router.navigate(to: .libraryBrowser(itemId: item.id, serverId: item.serverId))
        default:
            router.navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId))
        }
    }
}

// MARK: - Library Poster Card

private struct LibraryPosterCard: View {
    let item: ServerItem
    let imageUrl: String?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let metadata: String
    let watchedIndicator: WatchedIndicatorBehavior
    let showLabels: Bool
    let onFocused: (ServerItem) -> Void
    let onTap: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .bottom) {
                    posterImage
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))

                    if item.userData?.isFavorite == true {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.colorRed300)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(4)
                    }

                    watchIndicator
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(4)

                    if let pct = playedPercentage {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 4)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(theme.accent)
                                        .frame(width: geo.size.width * CGFloat(pct), height: 4)
                                }
                                .padding(.horizontal, SpaceTokens.spaceXs)
                                .padding(.bottom, SpaceTokens.spaceXs)
                            }
                        }
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))

                if showLabels {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: cardWidth)
            .padding(6)
        }
        .buttonStyle(LibraryCardButtonStyle(isFocused: isFocused, focusBorderColor: theme.focusBorder.color))
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused(item) }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let urlString = imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Color.white.opacity(0.06)
                default:
                    Color.white.opacity(0.06).shimmering()
                }
            }
        } else {
            Color.white.opacity(0.06)
        }
    }

    @ViewBuilder
    private var watchIndicator: some View {
        let isPlayed = item.userData?.played == true
        let unplayed = item.userData?.unplayedItemCount

        if watchedIndicator == .never
            || (watchedIndicator == .episodesOnly && item.type != .episode) {
            EmptyView()
        } else if isPlayed {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
        } else if let count = unplayed, count > 0, watchedIndicator != .hideAfterWatched {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var playedPercentage: Float? {
        guard let pct = item.userData?.playedPercentage else { return nil }
        let val = Float(pct) / 100.0
        guard val > 0 && val < 1 else { return nil }
        return val
    }
}

// MARK: - Library Card Button Style

private struct LibraryCardButtonStyle: ButtonStyle {
    let isFocused: Bool
    let focusBorderColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small + 6)
                    .stroke(isFocused ? focusBorderColor : .clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Toolbar Icon Button

struct ToolbarIconButton: View {
    let systemImage: String
    let isActive: Bool
    let theme: MoonfinTheme
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundColor(iconColor)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(bgColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: 3)
                )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }

    private var bgColor: Color {
        if isFocused { return .white }
        if isActive { return .white.opacity(0.15) }
        return .clear
    }

    private var iconColor: Color {
        if isFocused { return .black }
        if isActive { return theme.accent }
        return .white.opacity(0.5)
    }
}

// MARK: - Alpha Picker Letter

private struct AlphaLetterButtonStyle: ButtonStyle {
    let theme: MoonfinTheme
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFocused ? Color.white : .clear)
            )
            .scaleEffect(isFocused ? 1.2 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isFocused)
    }
}

private struct AlphaPickerLetter: View {
    let letter: String
    let isSelected: Bool
    let theme: MoonfinTheme
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(.system(size: 22, weight: isSelected ? .bold : .medium))
                .foregroundColor(letterColor)
                .frame(width: 38, height: 40)
        }
        .buttonStyle(AlphaLetterButtonStyle(theme: theme, isFocused: isFocused))
        .focused($isFocused)
    }

    private var letterColor: Color {
        if isFocused { return .black }
        if isSelected { return theme.accent }
        return .white.opacity(0.4)
    }
}

// MARK: - Filter/Sort Dialog

struct FilterSortDialogView: View {
    let sortOptions: [SortOption]
    let currentSort: SortOption
    let filterFavorites: Bool
    let filterUnwatched: Bool
    let showUnwatchedToggle: Bool
    let onSortSelected: (SortOption) -> Void
    let onToggleFavorites: () -> Void
    let onToggleUnwatched: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sort & Filter")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.08))

            Text("SORT BY")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            ForEach(sortOptions, id: \.sortBy) { option in
                let isSelected = option.sortBy == currentSort.sortBy
                Button(action: {
                    onSortSelected(option)
                    dismiss()
                }) {
                    HStack(spacing: 16) {
                        Circle()
                            .stroke(isSelected ? Color(hex: 0x00A4DC) : .white.opacity(0.3), lineWidth: 2)
                            .frame(width: 18, height: 18)
                            .overlay(
                                isSelected ?
                                    Circle().fill(Color(hex: 0x00A4DC)).frame(width: 10, height: 10)
                                    : nil
                            )

                        Text(option.name)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? Color(hex: 0x00A4DC) : .white.opacity(0.8))

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SortRowButtonStyle())
            }

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, 24)

            Text("FILTERS")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            filterToggleRow(label: "Favorites Only", isActive: filterFavorites, action: onToggleFavorites)

            if showUnwatchedToggle {
                filterToggleRow(label: "Unwatched Only", isActive: filterUnwatched, action: onToggleUnwatched)
            }

            Spacer()
        }
        .frame(minWidth: 340, maxWidth: 440)
        .background(Color(red: 0.078, green: 0.078, blue: 0.078).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func filterToggleRow(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color(hex: 0x00A4DC) : .clear)
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isActive ? Color.clear : .white.opacity(0.3), lineWidth: 2)
                    )
                    .overlay(
                        isActive ?
                            Text("").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                            : nil
                    )

                Text(label)
                    .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? Color(hex: 0x00A4DC) : .white.opacity(0.8))

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(SortRowButtonStyle())
    }
}

struct SortRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFocused ? Color.white.opacity(0.2) : (configuration.isPressed ? Color.white.opacity(0.12) : .clear))
            )
    }
}

// MARK: - Display Settings Dialog

struct DisplaySettingsDialogView: View {
    let posterSize: PosterSize
    let imageType: ImageDisplayType
    let onPosterSizeChanged: (PosterSize) -> Void
    let onImageTypeChanged: (ImageDisplayType) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Display Settings")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.08))

            Text("POSTER SIZE")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            ForEach(PosterSize.allCases, id: \.self) { size in
                let isSelected = size == posterSize
                Button(action: {
                    onPosterSizeChanged(size)
                    dismiss()
                }) {
                    HStack(spacing: 16) {
                        Circle()
                            .stroke(isSelected ? Color(hex: 0x00A4DC) : .white.opacity(0.3), lineWidth: 2)
                            .frame(width: 18, height: 18)
                            .overlay(
                                isSelected ?
                                    Circle().fill(Color(hex: 0x00A4DC)).frame(width: 10, height: 10)
                                    : nil
                            )

                        Text(size.displayName)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? Color(hex: 0x00A4DC) : .white.opacity(0.8))

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SortRowButtonStyle())
            }

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, 24)

            Text("IMAGE TYPE")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            ForEach(ImageDisplayType.allCases, id: \.self) { type in
                let isSelected = type == imageType
                Button(action: {
                    onImageTypeChanged(type)
                    dismiss()
                }) {
                    HStack(spacing: 16) {
                        Circle()
                            .stroke(isSelected ? Color(hex: 0x00A4DC) : .white.opacity(0.3), lineWidth: 2)
                            .frame(width: 18, height: 18)
                            .overlay(
                                isSelected ?
                                    Circle().fill(Color(hex: 0x00A4DC)).frame(width: 10, height: 10)
                                    : nil
                            )

                        Text(type.displayName)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? Color(hex: 0x00A4DC) : .white.opacity(0.8))

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SortRowButtonStyle())
            }

            Spacer()
        }
        .frame(minWidth: 340, maxWidth: 440)
        .background(Color(red: 0.078, green: 0.078, blue: 0.078).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
