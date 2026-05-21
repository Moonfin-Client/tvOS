import SwiftUI

struct ContentRow: View {
    let row: HomeRow
    let viewModel: HomeViewModel
    var watchedIndicator: WatchedIndicatorBehavior = .always
    var titleTopPadding: CGFloat = 0
    var onRowFocused: (() -> Void)?
    var onItemFocused: ((ServerItem) -> Void)?
    var onItemSelected: ((ServerItem) -> Void)?
    var onToggleWatched: ((ServerItem) -> Void)?
    var onToggleFavorite: ((ServerItem) -> Void)?
    var restoredItemId: String?
    var preferredItemId: String?
    var focusTrigger: Int = 0
    var transitionToken: Int = 0
    var isRowFocused: Bool = false
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @State private var v2FocusedItemId: String? = nil
    @State private var v2BackdropItemId: String? = nil
    @State private var v2BackdropSwitchTask: Task<Void, Never>? = nil

    private let v2ExtendedSectionHeight: CGFloat = 320
    private let v2BackdropSwitchDelayNs: UInt64 = 90_000_000

    private var posterSize: PosterSize {
        container.userPreferences[UserPreferences.homePosterSize]
    }

    private var isV2Mode: Bool {
        container.userPreferences[UserPreferences.homeRowsStyle] == .v2
    }

    private var isV2EligibleRow: Bool {
        isV2Mode && isCustomizableRow && row.rowType != .myMediaSmall && !isMusicRow
    }

    private var v2CardHeight: CGFloat {
        300 * posterSize.scaleFactor
    }

    private var v2PortraitWidth: CGFloat {
        v2CardHeight * (2.0 / 3.0)
    }

    private var v2FocusedWidth: CGFloat {
        v2CardHeight * (16.0 / 9.0)
    }

    private var v2FocusAnimation: Animation {
        .easeInOut(duration: 0.2)
    }

    private var imageDisplayType: ImageDisplayType {
        switch row.rowType {
        case .continueWatching, .resumeBook:
            return container.userPreferences[UserPreferences.homeImageTypeContinueWatching]
        case .nextUp:
            return container.userPreferences[UserPreferences.homeImageTypeNextUp]
        case .myMedia:
            return container.userPreferences[UserPreferences.homeImageTypeMyMedia]
        case .liveTvOnNow, .liveTvComingUp:
            return container.userPreferences[UserPreferences.homeImageTypeLiveTv]
        default:
            return container.userPreferences[UserPreferences.homeImageTypeLibraries]
        }
    }

    private var resolvedImageDisplayType: ImageDisplayType {
        isMusicRow ? .poster : imageDisplayType
    }

    private var isCustomizableRow: Bool {
        switch row.rowType {
        case .liveTvButtons:
            return false
        default:
            return true
        }
    }

    private var isMusicRow: Bool {
        switch row.rowType {
        case .resumeAudio, .playlists:
            return true
        case .latestMedia:
            if row.isMusicLibraryRow { return true }
            guard let first = row.items.first else { return false }
            return isMusicItem(first)
        default:
            return false
        }
    }

    private var effectiveAspectRatio: CGFloat {
        if isV2EligibleRow { return 2.0 / 3.0 }
        if isMusicRow { return 1.0 }
        return isCustomizableRow ? imageDisplayType.aspectRatio : row.rowType.aspectRatio
    }

    private var effectiveCardWidth: CGFloat {
        if isV2EligibleRow {
            return v2PortraitWidth
        }

        if effectiveAspectRatio >= 0.95 && effectiveAspectRatio <= 1.05 {
            // Keep all square-like rows visually consistent and larger.
            return 220 * posterSize.scaleFactor
        }

        let base: CGFloat = isCustomizableRow
            ? resolvedImageDisplayType.aspectRatio >= 1.0 ? 280 : 150
            : row.rowType.cardWidth
        return base * posterSize.scaleFactor
    }

    private var validRestoredItemId: String? {
        guard let restoredItemId else { return nil }
        return row.items.contains(where: { $0.id == restoredItemId }) ? restoredItemId : nil
    }

    var body: some View {
        Group {
            if row.isLoading {
                loadingRow
            } else if !row.items.isEmpty {
                itemRow
            }
        }
        .onChange(of: isRowFocused) { focused in
            if !focused {
                v2BackdropSwitchTask?.cancel()
                v2BackdropSwitchTask = nil
                v2BackdropItemId = nil
            }
        }
    }

    private var rowTitle: some View {
        Text(row.title)
            .font(.bodyLg)
            .fontWeight(.semibold)
            .foregroundColor(theme.colorScheme.onBackground)
            .padding(.top, titleTopPadding)
    }

    private var loadingRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .fill(theme.colorScheme.surface.opacity(0.2))
                            .aspectRatio(effectiveAspectRatio, contentMode: .fit)
                            .frame(width: effectiveCardWidth)
                            .shimmering()
                    }
                }
            }
        }
    }

    private var itemRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle

            ScrollViewReader { _ in
                FocusFirstRow(
                    firstItemId: row.items.first?.id,
                    restoredItemId: validRestoredItemId,
                    preferredItemId: preferredItemId,
                    focusTrigger: focusTrigger,
                    transitionToken: transitionToken,
                    applyFocusSection: false
                ) { focusBinding in
                    LazyHStack(alignment: .top, spacing: SpaceTokens.spaceMd) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                            cardView(for: item)
                                .id(item.id)
                                .focused(focusBinding, equals: item.id)
                                .onAppear {
                                    viewModel.loadMoreIfNeeded(row: row, currentIndex: index)
                                }
                        }
                    }
                    .padding(.vertical, isV2EligibleRow ? 20 : 12)
                    .padding(.horizontal, 12)
                }
                .modifier(ScrollClipDisabledModifier())
            }
        }
        .focusSection()
    }

    @ViewBuilder
    private func cardView(for item: ServerItem) -> some View {
        if row.rowType == .myMediaSmall {
            LibraryActionCard(
                item: item,
                cardWidth: effectiveCardWidth,
                onFocused: {
                    viewModel.onItemFocused(item)
                    onItemFocused?(item)
                    onRowFocused?()
                },
                onSelect: { onItemSelected?(item) }
            )
        } else if row.rowType == .liveTvButtons {
            LiveTvActionCard(
                item: item,
                cardWidth: row.rowType.cardWidth * posterSize.scaleFactor,
                aspectRatio: row.rowType.aspectRatio,
                onFocused: {
                    onItemFocused?(item)
                    onRowFocused?()
                },
                onSelect: { onItemSelected?(item) }
            )
        } else if isV2EligibleRow {
            v2CardView(for: item)
        } else {
            ItemPreview(
                item: item,
                imageUrl: imageUrl(for: item),
                aspectRatio: effectiveAspectRatio,
                cardWidth: effectiveCardWidth,
                watchedIndicator: watchedIndicator,
                serverName: viewModel.serverName(for: item),
                showLabels: row.rowType != .myMedia,
                onFocused: { item in
                    viewModel.onItemFocused(item)
                    onItemFocused?(item)
                    onRowFocused?()
                },
                onSelect: { onItemSelected?(item) },
                onToggleWatched: onToggleWatched.map { cb in { cb(item) } },
                onToggleFavorite: onToggleFavorite.map { cb in { cb(item) } }
            )
        }
    }

    private func v2CardView(for item: ServerItem) -> some View {
        let isFocused = isRowFocused && v2FocusedItemId == item.id
        let targetCardWidth = isFocused ? v2FocusedWidth : v2PortraitWidth
        let cardWidth = (targetCardWidth.isFinite && targetCardWidth > 1) ? targetCardWidth : max(1, v2PortraitWidth)
        let aspectRatio: CGFloat = isFocused ? (16.0 / 9.0) : (2.0 / 3.0)

        return VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            ItemPreview(
                item: item,
                imageUrl: v2ImageUrl(for: item, isFocused: isFocused),
                aspectRatio: aspectRatio,
                cardWidth: cardWidth,
                watchedIndicator: watchedIndicator,
                serverName: viewModel.serverName(for: item),
                focusScale: 1.0,
                showLabels: false,
                onFocused: { focusedItem in
                    viewModel.onItemFocused(focusedItem)
                    onItemFocused?(focusedItem)
                    onRowFocused?()
                },
                onFocusChange: { focused in
                    if focused {
                        v2FocusedItemId = item.id
                        v2BackdropSwitchTask?.cancel()
                        v2BackdropSwitchTask = Task {
                            try? await Task.sleep(nanoseconds: v2BackdropSwitchDelayNs)
                            guard !Task.isCancelled else { return }
                            if v2FocusedItemId == item.id {
                                v2BackdropItemId = item.id
                            }
                        }
                    }
                },
                onSelect: { onItemSelected?(item) },
                onToggleWatched: onToggleWatched.map { cb in { cb(item) } },
                onToggleFavorite: onToggleFavorite.map { cb in { cb(item) } }
            )

            HomeRowV2ExtendedSection(
                item: item,
                isVisible: isFocused,
                width: cardWidth,
                height: v2ExtendedSectionHeight,
                ratings: viewModel.mediaBarRatingsViewModel.ratings,
                enableAdditionalRatings: viewModel.mediaBarRatingsViewModel.enableAdditionalRatings
            )
        }
        .frame(width: cardWidth, alignment: .leading)
        .animation(v2FocusAnimation, value: isFocused)
    }

    private func v2ImageUrl(for item: ServerItem, isFocused: Bool) -> String? {
        if isFocused, v2BackdropItemId == item.id {
            return viewModel.thumbImageUrl(for: item) ?? viewModel.posterImageUrl(for: item)
        }
        return viewModel.posterImageUrl(for: item)
    }

    private func imageUrl(for item: ServerItem) -> String? {
        if item.type == .photo || item.mediaType == .photo {
            return viewModel.thumbImageUrl(for: item)
        }

        switch resolvedImageDisplayType {
        case .thumb:
            return viewModel.thumbImageUrl(for: item)
        case .banner:
            return viewModel.bannerImageUrl(for: item)
        default:
            return viewModel.posterImageUrl(for: item)
        }
    }

    private func isMusicItem(_ item: ServerItem) -> Bool {
        switch item.type {
        case .audio, .musicAlbum, .musicArtist, .musicVideo, .musicGenre:
            return true
        default:
            return false
        }
    }
}

private struct HomeRowV2ExtendedSection: View {
    let item: ServerItem
    let isVisible: Bool
    let width: CGFloat
    let height: CGFloat
    let ratings: [(String, Float)]
    let enableAdditionalRatings: Bool

    @EnvironmentObject var theme: MoonfinTheme

    private var safeWidth: CGFloat {
        if width.isFinite, width > 1 {
            return width
        }
        return 1
    }

    private var safeHeight: CGFloat {
        if height.isFinite, height > 1 {
            return height
        }
        return 1
    }

    private var contentWidth: CGFloat {
        safeWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            if let metadataText {
                Text(metadataText)
                    .font(.captionSm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.75))
                    .lineLimit(1)
            }

            if let officialRatingText {
                HStack(spacing: SpaceTokens.spaceXs) {
                    Text(officialRatingText)
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                        .padding(.horizontal, SpaceTokens.spaceSm)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                                .stroke(theme.colorScheme.onBackground.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            MediaBarRatingsRow(
                ratings: ratings,
                enableAdditionalRatings: enableAdditionalRatings
            )

            if let overviewText {
                Text(overviewText)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(4, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(width: contentWidth, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .frame(width: contentWidth, alignment: .topLeading)
        .frame(width: safeWidth, height: safeHeight, alignment: .topLeading)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var metadataText: String? {
        var parts: [String] = []

        if let yearText {
            parts.append(yearText)
        }

        if let firstGenre = item.genres?.first, !firstGenre.isEmpty {
            parts.append(firstGenre)
        }

        if let runtimeText {
            parts.append(runtimeText)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    private var yearText: String? {
        if let year = item.productionYear, year > 0 {
            return String(year)
        }
        if let date = item.premiereDate {
            return String(Calendar.current.component(.year, from: date))
        }
        return nil
    }

    private var runtimeText: String? {
        guard let ticks = item.runTimeTicks, ticks > 0 else { return nil }
        return RuntimeFormatter.format(ticks: ticks)
    }

    private var officialRatingText: String? {
        guard let rating = item.officialRating?.trimmingCharacters(in: .whitespacesAndNewlines), !rating.isEmpty else {
            return nil
        }
        return rating
    }

    private var overviewText: String? {
        guard let overview = item.overview?.trimmingCharacters(in: .whitespacesAndNewlines), !overview.isEmpty else {
            return nil
        }
        return overview
    }
}

struct LibraryActionCard: View {
    let item: ServerItem
    let cardWidth: CGFloat
    let onFocused: () -> Void
    let onSelect: () -> Void
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private var iconName: String {
        guard let ct = item.collectionType?.lowercased() else { return "folder" }
        switch ct {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "music": return "music.note"
        case "books": return "book"
        case "photos": return "photo"
        case "homevideos": return "video"
        case "boxsets": return "square.stack"
        case "playlists": return "list.bullet"
        case "livetv": return "antenna.radiowaves.left.and.right"
        default: return "folder"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(isFocused ? .white : theme.accent)
                Text(item.name)
                    .font(.bodyMd)
                    .fontWeight(.semibold)
                    .foregroundColor(isFocused ? .white : theme.colorScheme.onBackground)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(SpaceTokens.spaceSm)
            .frame(width: cardWidth, height: cardWidth)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(isFocused ? theme.accent : theme.colorScheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused() }
        }
    }
}

struct LiveTvActionCard: View {
    let item: ServerItem
    let cardWidth: CGFloat
    let aspectRatio: CGFloat
    let onFocused: () -> Void
    let onSelect: () -> Void
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private var iconName: String {
        switch item.id {
        case "ltv_guide": return "calendar"
        case "ltv_recordings": return "recordingtape"
        case "ltv_schedule": return "clock"
        case "ltv_series": return "rectangle.stack"
        default: return "tv"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(isFocused ? .white : theme.accent)
                Text(item.name)
                    .font(.bodyMd)
                    .fontWeight(.semibold)
                    .foregroundColor(isFocused ? .white : theme.colorScheme.onBackground)
            }
            .frame(width: cardWidth, height: cardWidth / aspectRatio)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(isFocused ? theme.accent : theme.colorScheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: isFocused ? theme.accent.opacity(0.5) : .clear, radius: 8)
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused() }
        }
    }
}

private struct ScrollClipDisabledModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(tvOS 17.0, *) {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: min(1, max(0, phase - 0.3))),
                        .init(color: .white.opacity(0.1), location: min(1, max(0, phase))),
                        .init(color: .clear, location: min(1, max(0, phase + 0.3))),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
