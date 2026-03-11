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
        if let status = item.requestStatus {
            let (icon, color, text) = Self.requestStatusStyle(status)
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(text)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.85))
            .clipShape(Capsule())
            .padding(6)
        } else if item.isAvailable {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.colorGreen500)
                .padding(6)
        }
    }

    private static func requestStatusStyle(_ status: Int) -> (String, Color, String) {
        switch status {
        case SeerrRequestDto.statusPending: return ("clock.fill", .orange, "Pending")
        case SeerrRequestDto.statusApproved: return ("checkmark.circle.fill", .colorBlue500, "Approved")
        case SeerrRequestDto.statusDeclined: return ("xmark.circle.fill", .colorRed500, "Declined")
        case SeerrRequestDto.statusAvailable: return ("checkmark.circle.fill", .colorGreen500, "Available")
        default: return ("questionmark.circle.fill", .gray, "Unknown")
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

struct SeerrSettingsRowView: View {
    @ObservedObject var viewModel: SeerrDiscoverViewModel
    var onEditServerUrl: () -> Void
    var onSignIn: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text("Settings")
                .font(.bodyLg).fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SpaceTokens.spaceMd) {
                    SeerrSettingCard(
                        icon: "power",
                        title: "Enabled",
                        value: viewModel.settingsState.isEnabled ? "On" : "Off",
                        valueColor: viewModel.settingsState.isEnabled ? .colorGreen500 : .gray,
                        action: { viewModel.toggleEnabled() }
                    )

                    SeerrSettingCard(
                        icon: "globe",
                        title: "Server URL",
                        value: viewModel.settingsState.serverUrl.isEmpty ? "Not Set" : truncateUrl(viewModel.settingsState.serverUrl),
                        action: onEditServerUrl
                    )

                    SeerrSettingCard(
                        icon: "person.crop.circle",
                        title: "Sign In",
                        value: viewModel.settingsState.isConnected ? "Connected" : "Not Connected",
                        valueColor: viewModel.settingsState.isConnected ? .colorGreen500 : .orange,
                        subtitle: viewModel.settingsState.isConnecting ? "Connecting..." : viewModel.settingsState.connectionStatus,
                        action: onSignIn
                    )

                    SeerrSettingCard(
                        icon: "number.circle",
                        title: "Fetch Limit",
                        value: viewModel.settingsState.fetchLimit.displayName,
                        action: { viewModel.cycleFetchLimit() }
                    )

                    SeerrSettingCard(
                        icon: "eye.slash",
                        title: "NSFW Filter",
                        value: viewModel.settingsState.blockNsfw ? "On" : "Off",
                        valueColor: viewModel.settingsState.blockNsfw ? .colorGreen500 : .gray,
                        action: { viewModel.toggleNsfw() }
                    )
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
        }
    }

    private func truncateUrl(_ url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if cleaned.count > 25 { return String(cleaned.prefix(22)) + "..." }
        return cleaned
    }
}

struct SeerrSettingCard: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = .white
    var subtitle: String? = nil
    var action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 100

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.accent)
                    Text(title)
                        .font(.captionSm).fontWeight(.medium)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                }
                Text(value)
                    .font(.titleSm).fontWeight(.semibold)
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .padding(12)
            .background(theme.colorScheme.surface.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
        }
        .buttonStyle(ItemCardButtonStyle(
            isFocused: isFocused,
            cornerRadius: RadiusTokens.small,
            focusBorderColor: theme.focusBorder.color
        ))
        .focused($isFocused)
    }
}
