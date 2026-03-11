import SwiftUI

struct SeerrMediaDetailsView: View {
    @StateObject private var viewModel: SeerrMediaDetailsViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

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
        .onAppear { viewModel.loadDetails() }
        .sheet(isPresented: $viewModel.showSeasonPicker) { seasonPickerSheet }
        .sheet(isPresented: $viewModel.showAdvancedOptions) { advancedOptionsSheet }
        .sheet(isPresented: $viewModel.showQualityPicker) { qualityPickerSheet }
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
                        ImageProcessors.Resize(size: size, contentMode: .aspectFill),
                        ImageProcessors.GaussianBlur(radius: 12)
                    ]
                )
                .frame(width: size.width, height: size.height)
                .clipped()
                .drawingGroup()
            }
        }
        .background(theme.colorScheme.background)
    }

    private var gradientOverlay: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: theme.colorScheme.background.opacity(0.7), location: 0),
                    .init(color: theme.colorScheme.background.opacity(0.4), location: 0.3),
                    .init(color: theme.colorScheme.background.opacity(0.5), location: 0.6),
                    .init(color: theme.colorScheme.background.opacity(0.9), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    .init(color: theme.colorScheme.background.opacity(0.8), location: 0),
                    .init(color: .clear, location: 0.5)
                ],
                startPoint: .leading,
                endPoint: .trailing
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
                .padding(.leading, 50)
                .padding(.top, 60)

            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                statusBadge

                Text(viewModel.displayTitle)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(2)

                if let tagline = viewModel.tagline, !tagline.isEmpty {
                    Text(tagline)
                        .font(.titleMd)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                        .italic()
                        .lineLimit(1)
                }

                metadataRow

                actionButtons
                    .padding(.top, SpaceTokens.spaceSm)

                if let error = viewModel.requestError {
                    Text(error)
                        .font(.captionXs)
                        .foregroundColor(.colorRed500)
                        .lineLimit(2)
                }
            }
            .padding(.top, 80)
            .padding(.trailing, 50)
        }
    }

    private var posterView: some View {
        Group {
            if let urlString = viewModel.posterUrl, let url = URL(string: urlString) {
                CachedImage(url: url)
                    .frame(width: 220, height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.medium))
            } else {
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(theme.colorScheme.surface.opacity(0.3))
                    .frame(width: 220, height: 330)
            }
        }
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
        HStack(spacing: SpaceTokens.spaceMd) {
            if let year = viewModel.year {
                metadataChip(year)
            }
            if let runtime = viewModel.runtimeText {
                metadataChip(runtime)
            }
            if let vote = viewModel.voteAverage, vote > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.captionXs)
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", vote))
                        .font(.titleSm)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                }
            }
            if viewModel.isTv, let episodes = viewModel.episodeCount {
                metadataChip("\(viewModel.seasonCount)S · \(episodes)E")
            }
        }
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(.titleSm)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
    }

    private var actionButtons: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            if viewModel.canRequestHd || viewModel.canRequest4k {
                Button(action: { viewModel.handleRequestTap() }) {
                    HStack(spacing: 6) {
                        if viewModel.isRequesting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text("Request")
                    }
                    .font(.titleSm).fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .disabled(viewModel.isRequesting)
                .buttonStyle(.borderedProminent)
                .tint(theme.colorScheme.accent)
            }

            if viewModel.hasPendingRequests {
                Button(action: { viewModel.cancelPendingRequests() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                        Text("Cancel Request")
                    }
                    .font(.titleSm)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .disabled(viewModel.isRequesting)
                .buttonStyle(.bordered)
            }
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
        .padding(.horizontal, 50)
        .padding(.bottom, 80)
    }

    private var overviewAndFacts: some View {
        HStack(alignment: .top, spacing: SpaceTokens.spaceLg) {
            if let overview = viewModel.overview, !overview.isEmpty {
                Text(overview)
                    .font(.titleMd)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.85))
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            mediaFactsSidebar
                .frame(width: 300)
        }
    }

    private var mediaFactsSidebar: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            if let vote = viewModel.voteAverage, vote > 0 {
                factRow(label: "TMDB Score", value: String(format: "%.1f / 10", vote))
            }
            if let status = viewModel.statusText {
                factRow(label: "Status", value: status)
            }
            if viewModel.isMovie {
                if let date = viewModel.movieDetails?.releaseDate {
                    factRow(label: "Release Date", value: formatDate(date))
                }
                if let runtime = viewModel.runtimeText {
                    factRow(label: "Runtime", value: runtime)
                }
                if let budget = viewModel.budgetText {
                    factRow(label: "Budget", value: budget)
                }
                if let revenue = viewModel.revenueText {
                    factRow(label: "Revenue", value: revenue)
                }
            } else {
                if let date = viewModel.tvDetails?.firstAirDate {
                    factRow(label: "First Aired", value: formatDate(date))
                }
                if let date = viewModel.tvDetails?.lastAirDate {
                    factRow(label: "Last Aired", value: formatDate(date))
                }
                if viewModel.seasonCount > 0 {
                    factRow(label: "Seasons", value: "\(viewModel.seasonCount)")
                }
                if let eps = viewModel.episodeCount {
                    factRow(label: "Episodes", value: "\(eps)")
                }
                if !viewModel.networks.isEmpty {
                    factRow(label: "Networks", value: viewModel.networks.map(\.name).joined(separator: ", "))
                }
            }
            if let director = viewModel.director {
                factRow(label: "Director", value: director)
            }
        }
        .padding(SpaceTokens.spaceMd)
        .background(theme.colorScheme.surface.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
    }

    private func factRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.captionXs).fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            Text(value)
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.85))
        }
    }

    @ViewBuilder
    private var genresSection: some View {
        let genres = viewModel.genres
        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                sectionTitle("Genres")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpaceTokens.spaceSm) {
                        ForEach(genres) { genre in
                            Button(action: {
                                router.navigate(to: .seerrBrowseBy(
                                    filterId: genre.id,
                                    filterName: genre.name,
                                    mediaType: viewModel.isMovie ? "movie" : "tv"
                                ))
                            }) {
                                Text(genre.name)
                                    .font(.bodySm)
                                    .foregroundColor(theme.colorScheme.onBackground)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(theme.colorScheme.surface.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: SpaceTokens.spaceMd) {
                        ForEach(cast) { member in
                            SeerrCastCard(member: member) {
                                router.navigate(to: .seerrPersonDetails(personId: member.id))
                            }
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
        ScrollView(.horizontal, showsIndicators: false) {
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpaceTokens.spaceSm) {
                        ForEach(keywords) { keyword in
                            Button(action: {
                                router.navigate(to: .seerrBrowseBy(
                                    filterId: keyword.id,
                                    filterName: keyword.name,
                                    mediaType: viewModel.isMovie ? "movie" : "tv",
                                    filterType: "keyword"
                                ))
                            }) {
                                Text(keyword.name)
                                    .font(.captionXs)
                                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(theme.colorScheme.surface.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
                                        ? theme.colorScheme.accent.opacity(0.3)
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
                    .tint(theme.colorScheme.accent)
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
                                                ? theme.colorScheme.accent.opacity(0.3)
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
                                                ? theme.colorScheme.accent.opacity(0.3)
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
                    .tint(theme.colorScheme.accent)
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

            HStack(spacing: SpaceTokens.spaceLg) {
                if viewModel.canRequestHd {
                    Button(action: { viewModel.beginRequest(is4k: false) }) {
                        VStack(spacing: SpaceTokens.spaceSm) {
                            Image(systemName: "film")
                                .font(.system(size: 36))
                            Text("Standard")
                                .font(.titleMd).fontWeight(.semibold)
                        }
                        .frame(width: 200, height: 120)
                    }
                    .buttonStyle(.bordered)
                }
                if viewModel.canRequest4k {
                    Button(action: { viewModel.beginRequest(is4k: true) }) {
                        VStack(spacing: SpaceTokens.spaceSm) {
                            Image(systemName: "4k.tv")
                                .font(.system(size: 36))
                            Text("4K")
                                .font(.titleMd).fontWeight(.semibold)
                        }
                        .frame(width: 200, height: 120)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(40)
        .background(theme.colorScheme.background)
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
