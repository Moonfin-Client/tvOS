import SwiftUI
import Nuke

struct SeerrMediaDetailsView: View {
    @StateObject private var viewModel: SeerrMediaDetailsViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var container: AppContainer

    private var navbarIsLeft: Bool {
        container.userPreferences[UserPreferences.navbarPosition] == .left
    }

    private var contentLeading: CGFloat {
        navbarIsLeft ? LeftSidebar.sidebarInset : 50
    }

    init(itemJson: String, seerrRepository: SeerrRepositoryProtocol) {
        let item: SeerrDiscoverItemDto
        if let data = itemJson.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(SeerrDiscoverItemDto.self, from: data) {
            item = decoded
        } else {
            item = SeerrDiscoverItemDto(id: 0, mediaType: nil, title: "Unknown", name: nil,
                                        posterPath: nil, backdropPath: nil, overview: nil,
                                        releaseDate: nil, firstAirDate: nil)
        }
        _viewModel = StateObject(wrappedValue: SeerrMediaDetailsViewModel(item: item, seerrRepository: seerrRepository))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                switch viewModel.state {
                case .loading:
                    loadingView
                case .error(let message):
                    errorView(message)
                case .loaded:
                    backdropLayer(size: geo.size)
                    gradientOverlay
                    contentScroll
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.loadDetails()
            if let server = container.serverRepository.currentServer.value {
                let client = container.serverClientFactory.client(for: server)
                viewModel.setServerClient(client)
            }
        }
        .onExitCommand {
            handleExitCommand()
        }
        .sheet(isPresented: $viewModel.showSeasonPicker) { seasonPickerSheet }
        .sheet(isPresented: $viewModel.showAdvancedOptions) { advancedOptionsSheet }
        .sheet(isPresented: $viewModel.showQualityPicker) { qualityPickerSheet }
    }

    private func handleExitCommand() {
        if viewModel.showQualityPicker {
            viewModel.showQualityPicker = false
            return
        }
        if viewModel.showAdvancedOptions {
            viewModel.showAdvancedOptions = false
            return
        }
        if viewModel.showSeasonPicker {
            viewModel.showSeasonPicker = false
            return
        }
        router.goBack()
    }

    private var loadingView: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()
            ProgressView().tint(theme.colorScheme.onBackground)
        }
    }

    private func errorView(_ message: String) -> some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()
            VStack(spacing: SpaceTokens.spaceMd) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
                Text(message)
                    .font(.titleMd)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(50)
        }
    }

    private func backdropLayer(size: CGSize) -> some View {
        Group {
            if let urlString = viewModel.backdropUrl, let url = URL(string: urlString) {
                CachedImage(
                    url: url,
                    processors: [
                        ImageProcessors.Resize(size: size, contentMode: .aspectFill)
                    ]
                )
                .frame(width: size.width, height: size.height)
                .clipped()
                .opacity(0.7)
                .drawingGroup()
            }
        }
        .background(theme.colorScheme.background)
    }

    private var gradientOverlay: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: theme.colorScheme.background.opacity(0.85), location: 0),
                    .init(color: theme.colorScheme.background.opacity(0.4), location: 0.3),
                    .init(color: theme.colorScheme.background.opacity(0.3), location: 0.6),
                    .init(color: theme.colorScheme.background.opacity(0.85), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: theme.colorScheme.background.opacity(0.5), location: 0.4),
                    .init(color: theme.colorScheme.background.opacity(0.95), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var contentScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                mainContentSection
                    .padding(.top, SpaceTokens.spaceLg)
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: SpaceTokens.spaceLg) {
            posterView
                .padding(.leading, contentLeading)
                .padding(.top, 60)

            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                statusBadge

                Text(viewModel.titleWithYear)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(2)

                metadataRow

                if let tagline = viewModel.tagline, !tagline.isEmpty {
                    Text("\"\(tagline)\"")
                        .font(.titleMd)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                        .italic()
                        .lineLimit(1)
                }

                if let error = viewModel.requestError {
                    Text(error)
                        .font(.captionXs)
                        .foregroundColor(.colorRed500)
                        .lineLimit(2)
                }
            }
            .padding(.top, 320)
            .padding(.trailing, 50)
        }
    }

    private var posterView: some View {
        Group {
            if let urlString = viewModel.posterUrl, let url = URL(string: urlString) {
                CachedImage(url: url)
                    .frame(width: 280, height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.medium))
            } else {
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(theme.colorScheme.surface.opacity(0.3))
                    .frame(width: 280, height: 420)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.mediaStatus.icon)
                .font(.captionXs)
            Text(viewModel.mediaStatus.text)
                .font(.captionXs).fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusBadgeColor.opacity(0.85))
        .clipShape(Capsule())
    }

    private var statusBadgeColor: Color {
        switch viewModel.mediaStatus.color {
        case .green: return .colorGreen500
        case .yellow: return .colorYellow500
        case .red: return .colorRed500
        case .blue: return .colorCyan500
        case .orange: return .colorOrange500
        case .gray: return .colorGrey500
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 4) {
            let parts = viewModel.metadataChips
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part)
                    .font(.titleSm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                if index < parts.count - 1 {
                    Text("•")
                        .font(.titleSm)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var actionButtons: some View {
        FocusFirstRow(firstItemId: "request") { focusBinding in
            HStack(alignment: .top, spacing: 12) {
                let canRequest = viewModel.canRequestHd || viewModel.canRequest4k
                SeerrActionButton(
                    icon: canRequest ? "plus.circle.fill" : viewModel.mediaStatus.icon,
                    label: canRequest ? "Request" : viewModel.mediaStatus.text,
                    action: { if canRequest { viewModel.handleRequestTap() } },
                    isLoading: viewModel.isRequesting
                )
                .id("request")
                .focused(focusBinding, equals: "request")
                .opacity(canRequest ? 1.0 : 0.5)

                if viewModel.hasPendingRequests {
                    SeerrActionButton(
                        icon: "trash",
                        label: "Cancel",
                        action: { viewModel.cancelPendingRequests() },
                        isLoading: viewModel.isRequesting
                    )
                    .id("cancel")
                    .focused(focusBinding, equals: "cancel")
                }

                SeerrActionButton(
                    icon: "film",
                    label: "Trailer",
                    action: {
                        if let key = viewModel.trailerYouTubeKey,
                           let url = URL(string: "https://www.youtube.com/watch?v=\(key)") {
                            UIApplication.shared.open(url)
                        }
                    }
                )
                .id("trailer")
                .focused(focusBinding, equals: "trailer")

                if viewModel.showPlayButton {
                    SeerrActionButton(
                        icon: "play.fill",
                        label: "Play",
                        action: {
                            if let jellyfinId = viewModel.jellyfinItemId {
                                router.navigate(to: .itemDetails(itemId: jellyfinId))
                            }
                        }
                    )
                    .id("play")
                    .focused(focusBinding, equals: "play")
                    .opacity(viewModel.jellyfinItemId != nil ? 1.0 : 0.5)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
    }

    private var mainContentSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
            overviewAndFacts
            genresSection
            castSection
            recommendationsSection
            similarSection
            keywordsSection
        }
        .padding(.leading, contentLeading)
        .padding(.trailing, 50)
        .padding(.bottom, 80)
    }

    private var overviewAndFacts: some View {
        HStack(alignment: .top, spacing: SpaceTokens.spaceLg) {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
                if let overview = viewModel.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.85))
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                actionButtons
            }
            .frame(maxWidth: .infinity)

            mediaFactsTable
                .frame(width: 340)
        }
    }

    @ViewBuilder
    private var mediaFactsTable: some View {
        let facts = buildFactRows()
        VStack(spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                HStack {
                    Text(fact.label)
                        .font(.captionSm).fontWeight(.semibold)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(fact.value)
                        .font(.captionSm)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if index < facts.count - 1 {
                    Divider()
                        .background(theme.colorScheme.onBackground.opacity(0.15))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.colorScheme.onBackground.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func buildFactRows() -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let vote = viewModel.voteAverage, vote > 0 {
            rows.append(("TMDB Score", String(format: "%.0f%%", vote * 10)))
        }
        if let status = viewModel.statusText {
            rows.append(("Status", status))
        }
        if viewModel.isMovie {
            if let date = viewModel.movieDetails?.releaseDate {
                rows.append(("Release Date", formatDate(date)))
            }
            if let revenue = viewModel.revenueText {
                rows.append(("Revenue", revenue))
            }
            if let runtime = viewModel.runtimeText {
                rows.append(("Runtime", runtime))
            }
            if let budget = viewModel.budgetText {
                rows.append(("Budget", budget))
            }
        } else {
            if let date = viewModel.tvDetails?.firstAirDate {
                rows.append(("First Aired", formatDate(date)))
            }
            if let date = viewModel.tvDetails?.lastAirDate {
                rows.append(("Last Aired", formatDate(date)))
            }
            if viewModel.seasonCount > 0 {
                rows.append(("Seasons", "\(viewModel.seasonCount)"))
            }
            if let eps = viewModel.episodeCount {
                rows.append(("Episodes", "\(eps)"))
            }
            if !viewModel.networks.isEmpty {
                rows.append(("Networks", viewModel.networks.map(\.name).joined(separator: ", ")))
            }
        }
        if let director = viewModel.director {
            rows.append(("Director", director))
        }
        return rows
    }

    @ViewBuilder
    private var genresSection: some View {
        let genres = viewModel.genres
        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                sectionTitle("Genres")
                FocusFirstRow(firstItemId: String(genres.first?.id ?? 0)) { focusBinding in
                    HStack(spacing: SpaceTokens.spaceSm) {
                        ForEach(genres) { genre in
                            SeerrGenrePill(genre: genre) {
                                router.navigate(to: .seerrBrowseBy(
                                    filterId: genre.id,
                                    filterName: genre.name,
                                    mediaType: viewModel.isMovie ? "movie" : "tv"
                                ))
                            }
                            .id(String(genre.id))
                            .focused(focusBinding, equals: String(genre.id))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var castSection: some View {
        let cast = viewModel.cast
        if !cast.isEmpty {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                sectionTitle("Cast")
                FocusFirstRow(firstItemId: String(cast.first?.id ?? 0)) { focusBinding in
                    LazyHStack(spacing: SpaceTokens.spaceMd) {
                        ForEach(cast) { member in
                            SeerrCastCard(member: member) {
                                router.navigate(to: .seerrPersonDetails(personId: member.id))
                            }
                            .id(String(member.id))
                            .focused(focusBinding, equals: String(member.id))
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        if !viewModel.recommendations.isEmpty {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                sectionTitle("Recommendations")
                relatedItemsRow(viewModel.recommendations)
            }
        }
    }

    @ViewBuilder
    private var similarSection: some View {
        if !viewModel.similar.isEmpty {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                sectionTitle("Similar")
                relatedItemsRow(viewModel.similar)
            }
        }
    }

    private func relatedItemsRow(_ items: [SeerrDiscoverItemDto]) -> some View {
        FocusFirstRow(firstItemId: String(items.first?.id ?? 0)) { focusBinding in
            LazyHStack(spacing: SpaceTokens.spaceMd) {
                ForEach(items) { relatedItem in
                    SeerrItemCard(
                        item: relatedItem,
                        posterUrl: relatedItem.posterPath.map { SeerrImageUrl.poster($0) },
                        onSelect: {
                            if let json = viewModel.itemJson(relatedItem) {
                                router.navigate(to: .seerrMediaDetails(itemJson: json))
                            }
                        }
                    )
                    .id(String(relatedItem.id))
                    .focused(focusBinding, equals: String(relatedItem.id))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var keywordsSection: some View {
        let keywords = viewModel.keywords
        if !keywords.isEmpty {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                sectionTitle("Keywords")
                FocusFirstRow(firstItemId: String(keywords.first?.id ?? 0)) { focusBinding in
                    HStack(spacing: SpaceTokens.spaceSm) {
                        ForEach(keywords) { keyword in
                            SeerrKeywordPill(keyword: keyword) {
                                router.navigate(to: .seerrBrowseBy(
                                    filterId: keyword.id,
                                    filterName: keyword.name,
                                    mediaType: viewModel.isMovie ? "movie" : "tv",
                                    filterType: "keyword"
                                ))
                            }
                            .id(String(keyword.id))
                            .focused(focusBinding, equals: String(keyword.id))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.bodyLg).fontWeight(.semibold)
            .foregroundColor(theme.colorScheme.onBackground)
    }

    private var seasonPickerSheet: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Text("Select Seasons")
                .font(.titleLg).fontWeight(.bold)
                .foregroundColor(theme.colorScheme.onBackground)

            let unavailable = viewModel.getUnavailableSeasons(is4k: viewModel.pendingIs4k)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: SpaceTokens.spaceSm) {
                    ForEach(1...max(viewModel.seasonCount, 1), id: \.self) { season in
                        let isUnavailable = unavailable.contains(season)
                        Button(action: {
                            if viewModel.selectedSeasons.contains(season) {
                                viewModel.selectedSeasons.remove(season)
                            } else {
                                viewModel.selectedSeasons.insert(season)
                            }
                        }) {
                            Text("Season \(season)")
                                .font(.bodySm)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    viewModel.selectedSeasons.contains(season)
                                        ? theme.accent.opacity(0.3)
                                        : theme.colorScheme.surface.opacity(0.2)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                                .foregroundColor(
                                    isUnavailable
                                        ? theme.colorScheme.onBackground.opacity(0.3)
                                        : theme.colorScheme.onBackground
                                )
                        }
                        .disabled(isUnavailable)
                    }
                }
            }
            .frame(maxHeight: 400)

            HStack(spacing: SpaceTokens.spaceMd) {
                Button("Select All") {
                    let available = Set((1...viewModel.seasonCount).filter { !unavailable.contains($0) })
                    viewModel.selectedSeasons = available
                }
                .buttonStyle(.bordered)

                Button("Confirm") { viewModel.confirmSeasonSelection() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .disabled(viewModel.selectedSeasons.isEmpty)
            }
        }
        .padding(40)
        .background(theme.colorScheme.background)
    }

    private var advancedOptionsSheet: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
            Text("Advanced Options")
                .font(.titleLg).fontWeight(.bold)
                .foregroundColor(theme.colorScheme.onBackground)

            if let details = viewModel.serverDetails {
                VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                    Text("Quality Profile")
                        .font(.bodySm).foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SpaceTokens.spaceSm) {
                            ForEach(details.profiles) { profile in
                                Button(action: { viewModel.advancedOptions.profileId = profile.id }) {
                                    Text(profile.name)
                                        .font(.bodySm)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            viewModel.advancedOptions.profileId == profile.id
                                                ? theme.accent.opacity(0.3)
                                                : theme.colorScheme.surface.opacity(0.2)
                                        )
                                        .foregroundColor(theme.colorScheme.onBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                    Text("Root Folder")
                        .font(.bodySm).foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SpaceTokens.spaceSm) {
                            ForEach(details.rootFolders) { folder in
                                Button(action: { viewModel.advancedOptions.rootFolderId = folder.id }) {
                                    Text(folder.path)
                                        .font(.bodySm)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            viewModel.advancedOptions.rootFolderId == folder.id
                                                ? theme.accent.opacity(0.3)
                                                : theme.colorScheme.surface.opacity(0.2)
                                        )
                                        .foregroundColor(theme.colorScheme.onBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                ProgressView().tint(theme.colorScheme.onBackground)
            }

            HStack {
                Spacer()
                Button("Skip") { viewModel.confirmAdvancedOptions() }
                    .buttonStyle(.bordered)
                Button("Confirm") { viewModel.confirmAdvancedOptions() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
            }
        }
        .padding(40)
        .background(theme.colorScheme.background)
    }

    private var qualityPickerSheet: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            Text("Select Quality")
                .font(.titleLg).fontWeight(.bold)
                .foregroundColor(theme.colorScheme.onBackground)

            VStack(spacing: SpaceTokens.spaceMd) {
                if viewModel.canRequestHd {
                    qualityOptionButton(
                        icon: "film",
                        title: viewModel.qualityOptionLabel(is4k: false),
                        subtitle: "Standard quality request",
                        action: { viewModel.beginRequest(is4k: false) }
                    )
                }

                if viewModel.canRequest4k {
                    qualityOptionButton(
                        icon: "4k.tv",
                        title: viewModel.qualityOptionLabel(is4k: true),
                        subtitle: "Ultra HD request",
                        action: { viewModel.beginRequest(is4k: true) }
                    )
                }

                if !viewModel.canRequestHd && !viewModel.canRequest4k {
                    Text("No request qualities are currently available.")
                        .font(.bodySm)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpaceTokens.spaceSm)
                }
            }
            .frame(maxWidth: 560)

            Button("Cancel") {
                viewModel.showQualityPicker = false
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
        .background(theme.colorScheme.background)
    }

    private func qualityOptionButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SpaceTokens.spaceMd) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.titleMd).fontWeight(.semibold)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.bodySm)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .foregroundColor(theme.colorScheme.onBackground)
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceMd)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(theme.colorScheme.surface.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
        }
        .buttonStyle(CleanButtonStyle())
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct SeerrKeywordPill: View {
    let keyword: SeerrKeywordDto
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            Text(keyword.name)
                .font(.captionXs)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.colorScheme.surface.opacity(0.2))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
                )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

private struct SeerrGenrePill: View {
    let genre: SeerrGenreDto
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            Text(genre.name)
                .font(.bodySm)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.colorScheme.surface.opacity(0.3))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
                )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

private struct SeerrActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var isLoading: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isFocused ? Color.white : Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .frame(width: 80, height: 80)

                    if isLoading {
                        ProgressView().tint(isFocused ? .black : .white)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 28))
                            .foregroundColor(isFocused ? .black : .white)
                    }
                }

                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(isFocused ? 1.0 : 0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 36, alignment: .top)
            }
            .frame(width: 90, alignment: .top)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
