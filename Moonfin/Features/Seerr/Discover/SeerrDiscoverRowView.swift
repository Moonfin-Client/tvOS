import SwiftUI

struct SeerrDiscoverRowView: View {
    let row: SeerrDiscoverRow
    let viewModel: SeerrDiscoverViewModel
    var onItemSelected: ((SeerrDiscoverItemDto) -> Void)?
    var onGenreSelected: ((SeerrGenreDto, String) -> Void)?
    var onStudioSelected: ((SeerrStudioDto) -> Void)?
    var onNetworkSelected: ((SeerrNetworkDto) -> Void)?

    @EnvironmentObject var theme: MoonfinTheme

    private var isGenreRow: Bool { row.rowType == .movieGenres || row.rowType == .seriesGenres }
    private var isStudioRow: Bool { row.rowType == .studios }
    private var isNetworkRow: Bool { row.rowType == .networks }
    private var genreMediaType: String { row.rowType == .seriesGenres ? "tv" : "movie" }

    var body: some View {
        if row.isLoading {
            loadingRow
        } else if isGenreRow && !row.genres.isEmpty {
            genreRow
        } else if isStudioRow && !row.studios.isEmpty {
            studioRow
        } else if isNetworkRow && !row.networks.isEmpty {
            networkRow
        } else if !row.items.isEmpty {
            itemRow
        }
    }

    private var rowTitle: some View {
        Text(row.title)
            .font(.bodyLg).fontWeight(.semibold)
            .foregroundColor(theme.colorScheme.onBackground)
    }

    private var loadingRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle
            FocusFirstRow(firstItemId: "loading-\(row.id)-0") { focusBinding in
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(0..<6, id: \.self) { index in
                        Button(action: {}) {
                            RoundedRectangle(cornerRadius: RadiusTokens.small)
                                .fill(theme.colorScheme.surface.opacity(0.2))
                                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                .frame(width: 150)
                                .shimmering()
                        }
                        .buttonStyle(CleanButtonStyle())
                        .id("loading-\(row.id)-\(index)")
                        .focused(focusBinding, equals: "loading-\(row.id)-\(index)")
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
        }
    }

    private var itemRow: some View {
        let firstItemFocusId = row.items.first.map { "item-\(row.id)-0-\($0.id)" }
        return VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle
            FocusFirstRow(firstItemId: firstItemFocusId) { focusBinding in
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(Array(row.items.enumerated()), id: \.offset) { index, item in
                        let focusId = "item-\(row.id)-\(index)-\(item.id)"
                        SeerrItemCard(
                            item: item,
                            posterUrl: viewModel.posterUrl(for: item),
                            onFocused: { viewModel.onItemFocused(item) },
                            onSelect: { onItemSelected?(item) }
                        )
                        .id(focusId)
                        .focused(focusBinding, equals: focusId)
                        .onAppear { viewModel.loadMoreIfNeeded(row: row, currentIndex: index) }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
        }
    }

    private var genreRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle
            FocusFirstRow(firstItemId: String(row.genres.first?.id ?? 0)) { focusBinding in
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(row.genres) { genre in
                        SeerrGenreCard(
                            genre: genre,
                            onFocused: { viewModel.onGenreFocused(genre, mediaType: genreMediaType) },
                            onSelect: { onGenreSelected?(genre, genreMediaType) }
                        )
                        .id(String(genre.id))
                        .focused(focusBinding, equals: String(genre.id))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
        }
    }

    private var studioRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle
            FocusFirstRow(firstItemId: String(row.studios.first?.id ?? 0)) { focusBinding in
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(row.studios) { studio in
                        SeerrNetworkStudioCard(
                            name: studio.name,
                            logoUrl: studio.logoPath,
                            onFocused: {},
                            onSelect: { onStudioSelected?(studio) }
                        )
                        .id(String(studio.id))
                        .focused(focusBinding, equals: String(studio.id))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
        }
    }

    private var networkRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle
            FocusFirstRow(firstItemId: String(row.networks.first?.id ?? 0)) { focusBinding in
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(row.networks) { network in
                        SeerrNetworkStudioCard(
                            name: network.name,
                            logoUrl: network.logoPath,
                            onFocused: {},
                            onSelect: { onNetworkSelected?(network) }
                        )
                        .id(String(network.id))
                        .focused(focusBinding, equals: String(network.id))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
        }
    }
}

struct SeerrItemCard: View {
    let item: SeerrDiscoverItemDto
    let posterUrl: String?
    var onFocused: (() -> Void)?
    var onSelect: (() -> Void)?

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat = 150
    private var cardHeight: CGFloat { cardWidth * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Button(action: { onSelect?() }) {
                ZStack {
                    posterImage

                    SeerrPosterBadgeOverlay(item: item)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
            }
            .buttonStyle(ItemCardButtonStyle(
                isFocused: isFocused,
                cornerRadius: RadiusTokens.small,
                focusBorderColor: theme.focusBorder.color
            ))
            .focused($isFocused)
            .onChange(of: isFocused) { focused in
                if focused { onFocused?() }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.mediaType == "tv" ? "Series" : "Movie")
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    if let year = extractYear(from: item) {
                        Text("•")
                            .font(.captionXs)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                        Text(year)
                            .font(.captionXs)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    }
                }
            }
            .frame(width: cardWidth, alignment: .leading)
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
                    placeholder
                case .empty:
                    placeholder.shimmering()
                @unknown default:
                    placeholder
                }
            }
            .frame(width: cardWidth, height: cardHeight)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(theme.colorScheme.surface.opacity(0.6))
            Image(systemName: item.mediaType == "tv" ? "tv" : "film")
                .font(.system(size: 28))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.3))
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private func extractYear(from item: SeerrDiscoverItemDto) -> String? {
        let date = item.releaseDate ?? item.firstAirDate
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
}

struct SeerrPosterBadgeOverlay: View {
    let item: SeerrDiscoverItemDto

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                mediaTypeBadge
                Spacer()
                statusBadge
            }
            Spacer()
        }
        .padding(6)
    }

    @ViewBuilder
    private var mediaTypeBadge: some View {
        if let mediaType = item.mediaType {
            let text = mediaType == "tv" ? "SERIES" : "MOVIE"
            let backgroundColor = mediaType == "tv" ? Color(hex: 0x8B5CF6) : Color(hex: 0x3B82F6)

            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .tracking(0.8)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(backgroundColor.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if item.isAvailable {
            circularStatusBadge(glyph: "checkmark", color: .colorGreen500)
        } else if let status = item.requestStatus {
            let (glyph, color) = seerrRequestStatusStyle(status)
            circularStatusBadge(glyph: glyph, color: color)
        }
    }

    private func circularStatusBadge(glyph: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
            Image(systemName: glyph)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 18, height: 18)
        .padding(6)
    }
}

private func seerrRequestStatusStyle(_ status: Int) -> (String, Color) {
    switch status {
    case SeerrRequestDto.statusPending: return ("clock.fill", .orange)
    case SeerrRequestDto.statusApproved: return ("checkmark", .colorBlue500)
    case SeerrRequestDto.statusDeclined: return ("xmark", .colorRed500)
    case SeerrRequestDto.statusAvailable: return ("checkmark", .colorGreen500)
    default: return ("questionmark", .gray)
    }
}

struct SeerrGenreCard: View {
    let genre: SeerrGenreDto
    var onFocused: (() -> Void)?
    var onSelect: (() -> Void)?

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 140

    var body: some View {
        Button(action: { onSelect?() }) {
            ZStack(alignment: .bottomLeading) {
                genreImage
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Text(genre.name)
                    .font(.titleMd)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(12)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
        }
        .buttonStyle(ItemCardButtonStyle(
            isFocused: isFocused,
            cornerRadius: RadiusTokens.small,
            focusBorderColor: theme.focusBorder.color
        ))
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused?() }
        }
    }

    @ViewBuilder
    private var genreImage: some View {
        if let path = genre.backdrops.first,
           let url = URL(string: SeerrImageUrl.genreBackdrop(path)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    genrePlaceholder
                case .empty:
                    genrePlaceholder.shimmering()
                @unknown default:
                    genrePlaceholder
                }
            }
            .frame(width: cardWidth, height: cardHeight)
        } else {
            genrePlaceholder
        }
    }

    private var genrePlaceholder: some View {
        Rectangle()
            .fill(theme.colorScheme.surface.opacity(0.3))
            .frame(width: cardWidth, height: cardHeight)
    }
}

struct SeerrNetworkStudioCard: View {
    let name: String
    let logoUrl: String?
    var onFocused: (() -> Void)?
    var onSelect: (() -> Void)?

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 140

    var body: some View {
        Button(action: { onSelect?() }) {
            ZStack {
                if let urlString = logoUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: cardWidth - 48, maxHeight: cardHeight - 48)
                        case .failure:
                            logoPlaceholder
                        case .empty:
                            logoPlaceholder.shimmering()
                        @unknown default:
                            logoPlaceholder
                        }
                    }
                } else {
                    logoPlaceholder
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(theme.colorScheme.surface.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
        }
        .buttonStyle(ItemCardButtonStyle(
            isFocused: isFocused,
            cornerRadius: RadiusTokens.small,
            focusBorderColor: theme.focusBorder.color
        ))
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocused?() }
        }
    }

    private var logoPlaceholder: some View {
        Image(systemName: "building.2")
            .font(.system(size: 28))
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
    }
}
