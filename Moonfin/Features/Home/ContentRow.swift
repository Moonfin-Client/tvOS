import SwiftUI

struct ContentRow: View {
    let row: HomeRow
    let viewModel: HomeViewModel
    var watchedIndicator: WatchedIndicatorBehavior = .always
    var onRowFocused: (() -> Void)?
    var onItemSelected: ((ServerItem) -> Void)?
    var restoredItemId: String?
    var focusTrigger: Int = 0
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer

    private var posterSize: PosterSize {
        container.userPreferences[UserPreferences.homePosterSize]
    }

    private var imageDisplayType: ImageDisplayType {
        container.userPreferences[UserPreferences.homeRowsImageType]
    }

    private var isCustomizableRow: Bool {
        switch row.rowType {
        case .continueWatching, .nextUp, .liveTvButtons, .liveTvOnNow, .liveTvComingUp:
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
        if isMusicRow { return 1.0 }
        return isCustomizableRow ? imageDisplayType.aspectRatio : row.rowType.aspectRatio
    }

    private var effectiveCardWidth: CGFloat {
        let base: CGFloat = isCustomizableRow
            ? imageDisplayType.aspectRatio >= 1.0 ? 280 : 150
            : row.rowType.cardWidth
        return base * posterSize.scaleFactor
    }

    var body: some View {
        if row.isLoading {
            loadingRow
        } else if !row.items.isEmpty {
            itemRow
        }
    }

    private var rowTitle: some View {
        Text(row.title)
            .font(.bodyLg)
            .fontWeight(.semibold)
            .foregroundColor(theme.colorScheme.onBackground)
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

            ScrollViewReader { scrollProxy in
                FocusFirstRow(firstItemId: row.items.first?.id, focusTrigger: focusTrigger) { focusBinding in
                    LazyHStack(spacing: SpaceTokens.spaceMd) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                            cardView(for: item)
                                .id(item.id)
                                .focused(focusBinding, equals: item.id)
                                .onAppear {
                                    viewModel.loadMoreIfNeeded(row: row, currentIndex: index)
                                }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
                .modifier(ScrollClipDisabledModifier())
            }
        }
    }

    @ViewBuilder
    private func cardView(for item: ServerItem) -> some View {
        if row.rowType == .myMedia {
            LibraryCard(
                item: item,
                imageUrl: viewModel.thumbImageUrl(for: item),
                cardWidth: row.rowType.cardWidth * posterSize.scaleFactor,
                onFocused: { item in
                    viewModel.onItemFocused(item)
                    onRowFocused?()
                },
                onSelect: { onItemSelected?(item) }
            )
        } else if row.rowType == .myMediaSmall {
            LibraryActionCard(
                item: item,
                cardWidth: row.rowType.cardWidth * posterSize.scaleFactor,
                onFocused: {
                    viewModel.onItemFocused(item)
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
                    onRowFocused?()
                },
                onSelect: { onItemSelected?(item) }
            )
        } else {
            ItemPreview(
                item: item,
                imageUrl: imageUrl(for: item),
                aspectRatio: effectiveAspectRatio,
                cardWidth: effectiveCardWidth,
                watchedIndicator: watchedIndicator,
                serverName: viewModel.serverName(for: item),
                onFocused: { item in
                    viewModel.onItemFocused(item)
                    onRowFocused?()
                },
                onSelect: { onItemSelected?(item) }
            )
        }
    }

    private func imageUrl(for item: ServerItem) -> String? {
        switch row.rowType {
        case .continueWatching, .nextUp, .liveTvOnNow, .liveTvComingUp:
            return viewModel.thumbImageUrl(for: item)
        default:
            switch imageDisplayType {
            case .thumb:
                return viewModel.thumbImageUrl(for: item)
            default:
                return viewModel.posterImageUrl(for: item)
            }
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
