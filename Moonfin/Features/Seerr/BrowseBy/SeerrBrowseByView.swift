import SwiftUI
import Nuke

struct SeerrBrowseByView: View {
    @StateObject private var viewModel: SeerrBrowseByViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @State private var showSortDialog = false
    @State private var showDisplaySettings = false

    init(filterId: Int, filterName: String, mediaType: String, filterType: String,
         seerrRepository: SeerrRepositoryProtocol) {
        _viewModel = StateObject(wrappedValue: SeerrBrowseByViewModel(
            filterId: filterId, filterName: filterName,
            mediaType: mediaType, filterType: filterType,
            seerrRepository: seerrRepository
        ))
    }

    var body: some View {
        ZStack {
            backdropLayer
            overlayLayer

            VStack(spacing: 0) {
                browseHeader
                    .padding(.horizontal, 60)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                if viewModel.isLoading && viewModel.items.isEmpty {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if viewModel.items.isEmpty {
                    emptyView
                } else {
                    contentView
                }

                statusBar
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.loadInitial()
            router.pushNavbarHidden()
        }
        .onDisappear {
            router.popNavbarHidden()
        }
        .sheet(isPresented: $showSortDialog) { sortDialog }
        .sheet(isPresented: $showDisplaySettings) { displaySettingsDialog }
    }

    private var emptyView: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            Text(Strings.noItemsFound)
                .font(.bodyLg)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
    }

    private var contentView: some View {
        let dims = viewModel.cardDimensions
        let columns = [GridItem(.adaptive(minimum: dims.width + 32), spacing: 16)]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    SeerrBrowsePosterCard(
                        item: item,
                        posterUrl: item.posterPath.map { SeerrImageUrl.poster($0) },
                        cardWidth: dims.width,
                        cardHeight: dims.height,
                        metadata: viewModel.buildMetadata(for: item),
                        onFocused: { viewModel.setFocusedItem($0) },
                        onTap: {
                            if let json = viewModel.itemJson(item) {
                                router.navigate(to: .seerrMediaDetails(itemJson: json))
                            }
                        }
                    )
                    .onAppear {
                        if index >= viewModel.items.count - 10 {
                            viewModel.loadMore()
                        }
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
    }

    private var browseHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    Text(viewModel.filterName)
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.white)

                    if !viewModel.items.isEmpty {
                        Text(Strings.seerrItemsCount(viewModel.resultCountText))
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
            }
        }
    }

    private var focusedItemHud: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let item = viewModel.focusedItem {
                Text(item.displayTitle)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                SeerrBrowseInfoRow(item: item)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.bodyMd)
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(3)
                }
            }
        }
        .frame(height: 110, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolbarButtons: some View {
        HStack(spacing: 4) {
            ToolbarIconButton(
                systemImage: "house",
                isActive: false,
                theme: theme,
                action: { router.goBack() }
            )

            ToolbarIconButton(
                systemImage: "arrow.up.arrow.down",
                isActive: viewModel.activeFilter != .all,
                theme: theme,
                action: { showSortDialog = true }
            )

            ToolbarIconButton(
                systemImage: "gearshape",
                isActive: false,
                theme: theme,
                action: { showDisplaySettings = true }
            )
        }
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.statusText)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))

            Spacer()

            Text("\(viewModel.items.count) | \(viewModel.totalItemsCount)")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 4)
    }

    private var backdropLayer: some View {
        GeometryReader { geo in
            if let urlString = viewModel.backdropUrl,
               let url = URL(string: urlString) {
                CachedImage(
                    url: url,
                    processors: [
                        ImageProcessors.Resize(size: CGSize(width: geo.size.width, height: geo.size.height), contentMode: .aspectFill),
                        ImageProcessors.GaussianBlur(radius: 8)
                    ]
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .drawingGroup()
                .transition(.opacity)
                .id(urlString)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: viewModel.backdropUrl)
        .background(theme.colorScheme.background)
    }

    private var overlayLayer: some View {
        let hasBackdrop = viewModel.backdropUrl != nil
        let alpha = hasBackdrop ? 0.45 : 0.75
        return Color(red: 0.063, green: 0.082, blue: 0.157)
            .opacity(alpha)
            .ignoresSafeArea()
    }

    private var sortDialog: some View {
        SeerrFilterSortDialogView(
            sortOptions: SeerrBrowseSortOption.allCases,
            currentSort: viewModel.sortOption,
            activeFilter: viewModel.activeFilter,
            onSortSelected: { viewModel.changeSortOption($0) },
            onFilterSelected: { viewModel.changeFilter($0) }
        )
    }

    private var displaySettingsDialog: some View {
        SeerrDisplaySettingsDialogView(
            posterSize: viewModel.posterSize,
            onPosterSizeChanged: { viewModel.setPosterSize($0) }
        )
    }
}

private struct SeerrBrowseInfoRow: View {
    let item: SeerrDiscoverItemDto

    var body: some View {
        HStack(spacing: 10) {
            if let type = item.mediaType {
                Text(type == "tv" ? Strings.series : Strings.seerrMovie)
            }

            if let voteAverage = item.voteAverage, voteAverage > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                    Text(String(format: "%.1f", voteAverage))
                }
            }

            if let statusText {
                Text(statusText)
            }
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(.white.opacity(0.72))
    }

    private var statusText: String? {
        if item.isAvailable {
            return Strings.seerrStatusAvailable
        }

        guard let requestStatus = item.requestStatus else { return nil }
        switch requestStatus {
        case SeerrRequestDto.statusPending:
            return Strings.seerrStatusPending
        case SeerrRequestDto.statusApproved:
            return Strings.seerrStatusApproved
        case SeerrRequestDto.statusDeclined:
            return Strings.seerrStatusDeclined
        case SeerrRequestDto.statusAvailable:
            return Strings.seerrStatusAvailable
        default:
            return nil
        }
    }
}

private struct SeerrBrowsePosterCard: View {
    let item: SeerrDiscoverItemDto
    let posterUrl: String?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let metadata: String
    let onFocused: (SeerrDiscoverItemDto) -> Void
    let onTap: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    posterImage
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))

                    SeerrPosterBadgeOverlay(item: item)
                }
                .frame(width: cardWidth, height: cardHeight)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))

                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.colorScheme.listHeadline)
                    .lineLimit(1)

                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.system(size: 11))
                        .foregroundColor(theme.colorScheme.listCaption)
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth)
            .padding(6)
        }
        .buttonStyle(ItemCardButtonStyle(
            isFocused: isFocused,
            cornerRadius: RadiusTokens.small + 6,
            focusBorderColor: theme.effectiveFocusColor,
            focusGlow: theme.activeSpec.borders.focusGlow
        ))
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused {
                onFocused(item)
            }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let urlString = posterUrl, let url = URL(string: urlString) {
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
}

private struct SeerrFilterSortDialogView: View {
    let sortOptions: [SeerrBrowseSortOption]
    let currentSort: SeerrBrowseSortOption
    let activeFilter: SeerrBrowseFilter
    let onSortSelected: (SeerrBrowseSortOption) -> Void
    let onFilterSelected: (SeerrBrowseFilter) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.seerrSortAndFilter)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.08))

            Text(Strings.seerrSortByUpper)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            ForEach(sortOptions, id: \.self) { option in
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

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, 24)

            Text(Strings.seerrFiltersUpper)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            ForEach(SeerrBrowseFilter.allCases, id: \.self) { filter in
                let isSelected = filter == activeFilter
                Button(action: {
                    onFilterSelected(filter)
                    dismiss()
                }) {
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color(hex: 0x00A4DC) : .clear)
                            .frame(width: 18, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isSelected ? Color.clear : .white.opacity(0.3), lineWidth: 2)
                            )
                            .overlay(
                                isSelected ?
                                    Text("").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                                    : nil
                            )

                        Text(filter.displayName)
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

private struct SeerrDisplaySettingsDialogView: View {
    let posterSize: PosterSize
    let onPosterSizeChanged: (PosterSize) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.seerrDisplaySettings)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.08))

            Text(Strings.seerrPosterSizeUpper)
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
