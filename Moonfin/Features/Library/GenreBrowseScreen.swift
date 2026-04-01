import SwiftUI
import Nuke

struct GenreBrowseScreen: View {
    @StateObject private var viewModel: GenreBrowseViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @State private var showSortDialog = false
    @State private var showDisplaySettings = false

    init(container: AppContainer, parentId: String? = nil, includeType: String? = nil) {
        _viewModel = StateObject(wrappedValue: GenreBrowseViewModel(
            container: container, parentId: parentId, includeType: includeType
        ))
    }

    var body: some View {
        ZStack {
            backdropLayer
            overlayLayer

            VStack(spacing: 0) {
                genresHeader
                    .padding(.horizontal, 60)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                } else if viewModel.genres.isEmpty {
                    Spacer()
                    Text("No genres found")
                        .font(.bodyLg)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                } else {
                    genresGrid
                }

                statusBar
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.initialize()
            router.pushNavbarHidden()
        }
        .onDisappear {
            router.popNavbarHidden()
        }
        .sheet(isPresented: $showSortDialog) {
            GenreSortDialogView(
                currentSort: viewModel.currentSort,
                onSortSelected: { viewModel.setSortOption($0) }
            )
        }
        .sheet(isPresented: $showDisplaySettings) {
            GenreDisplaySettingsDialogView(
                posterSize: viewModel.posterSize,
                imageType: viewModel.imageType,
                onPosterSizeChanged: { viewModel.setPosterSize($0) },
                onImageTypeChanged: { viewModel.setImageType($0) }
            )
        }
    }

    // MARK: - Header

    private var genresHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    Text(viewModel.title)
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.white)

                    if viewModel.totalGenres > 0 {
                        Text("\(viewModel.totalGenres) Genres")
                            .font(.captionXs)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                Spacer()
            }

            focusedGenreHud

            HStack(spacing: 4) {
                ToolbarIconButton(
                    systemImage: "house",
                    isActive: false,
                    theme: theme,
                    action: { router.goBack() }
                )

                ToolbarIconButton(
                    systemImage: "arrow.up.arrow.down",
                    isActive: false,
                    theme: theme,
                    action: { showSortDialog = true }
                )

                ToolbarIconButton(
                    systemImage: "slider.horizontal.3",
                    isActive: false,
                    theme: theme,
                    action: { showDisplaySettings = true }
                )
            }
        }
    }

    private var focusedGenreHud: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let genre = viewModel.focusedGenre {
                Text(genre.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(genre.itemCount) Items")
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(height: 56, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Grid

    private var genresGrid: some View {
        let cardHeight: CGFloat = 220 * viewModel.posterSize.scaleFactor
        let cardAspectRatio: CGFloat = viewModel.imageType == .poster ? (2.0 / 3.0) : (16.0 / 9.0)
        let cardWidth: CGFloat = cardHeight * cardAspectRatio
        let columns = [GridItem(.adaptive(minimum: cardWidth + 24), spacing: 12)]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.genres) { genre in
                    GenreCard(
                        genre: genre,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        theme: theme,
                        onFocused: { viewModel.setFocusedGenre(genre) },
                        onTap: {
                            router.navigate(to: .genreBrowse(
                                genreName: genre.name,
                                parentId: genre.parentId,
                                includeType: viewModel.includeType,
                                serverId: genre.serverId
                            ))
                        }
                    )
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

            Text("\(viewModel.totalGenres) Genres")
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
}

// MARK: - Genre Card

private struct GenreCard: View {
    let genre: GenreItem
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let theme: MoonfinTheme
    let onFocused: () -> Void
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                if let urlString = genre.imageUrl ?? genre.backdropUrl, let url = URL(string: urlString) {
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

                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .init(x: 0.5, y: 0.4),
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(genre.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("\(genre.itemCount) Items")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(12)
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
        }
        .buttonStyle(GenreCardButtonStyle(isFocused: isFocused, focusBorderColor: theme.focusBorder.color))
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused() }
        }
    }
}

private struct GenreCardButtonStyle: ButtonStyle {
    let isFocused: Bool
    let focusBorderColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .stroke(isFocused ? focusBorderColor : .clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .opacity(isFocused ? 1.0 : 0.7)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Genre Sort Dialog

struct GenreSortDialogView: View {
    let currentSort: GenreSortOption
    let onSortSelected: (GenreSortOption) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sort Genres")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.08))

            ForEach(GenreSortOption.allCases, id: \.self) { option in
                let isSelected = option == currentSort
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

                        Text(option.displayName)
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

struct GenreDisplaySettingsDialogView: View {
    let posterSize: PosterSize
    let imageType: ImageDisplayType
    let onPosterSizeChanged: (PosterSize) -> Void
    let onImageTypeChanged: (ImageDisplayType) -> Void

    @Environment(\.dismiss) private var dismiss

    private var supportedPosterSizes: [PosterSize] {
        PosterSize.allCases
    }

    private var supportedImageTypes: [ImageDisplayType] {
        [.poster, .thumb, .banner]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Display Settings")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.08))

            Text("IMAGE TYPE")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            ForEach(supportedImageTypes, id: \.self) { type in
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

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, 24)

            Text("POSTER SIZE")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            ForEach(supportedPosterSizes, id: \.self) { size in
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
