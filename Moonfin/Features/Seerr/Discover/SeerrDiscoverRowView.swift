import SwiftUI

struct SeerrDiscoverRowView: View {
    let row: SeerrDiscoverRow
    let viewModel: SeerrDiscoverViewModel
    var onItemSelected: ((SeerrDiscoverItemDto) -> Void)?
    var onGenreSelected: ((SeerrGenreDto, String) -> Void)?

    @EnvironmentObject var theme: MoonfinTheme

    private var isGenreRow: Bool { row.rowType == .movieGenres || row.rowType == .seriesGenres }
    private var genreMediaType: String { row.rowType == .seriesGenres ? "tv" : "movie" }

    var body: some View {
        if row.isLoading {
            loadingRow
        } else if isGenreRow && !row.genres.isEmpty {
            genreRow
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
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .fill(theme.colorScheme.surface.opacity(0.2))
                            .aspectRatio(2.0 / 3.0, contentMode: .fit)
                            .frame(width: 150)
                            .shimmering()
                    }
                }
            }
        }
    }

    private var itemRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle
            FocusFirstRow(firstItemId: String(row.items.first?.id ?? 0)) { focusBinding in
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        SeerrItemCard(
                            item: item,
                            posterUrl: viewModel.posterUrl(for: item),
                            onFocused: { viewModel.onItemFocused(item) },
                            onSelect: { onItemSelected?(item) }
                        )
                        .id(String(item.id))
                        .focused(focusBinding, equals: String(item.id))
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
                ZStack(alignment: .bottomTrailing) {
                    posterImage
                    statusBadge
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
        Rectangle()
            .fill(theme.colorScheme.surface.opacity(0.3))
            .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if item.isAvailable {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.colorGreen500)
                .padding(6)
        }
    }

    private func extractYear(from item: SeerrDiscoverItemDto) -> String? {
        let date = item.releaseDate ?? item.firstAirDate
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
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
