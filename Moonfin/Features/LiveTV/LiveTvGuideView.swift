import SwiftUI

struct LiveTvGuideView: View {
    @StateObject private var viewModel: LiveTvGuideViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: LiveTvGuideViewModel(
            container: container
        ))
    }

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.channels.isEmpty {
                loadingView
            } else if let error = viewModel.error, viewModel.channels.isEmpty {
                errorView(error)
            } else {
                VStack(spacing: 0) {
                    guideHeader
                    guideGrid
                }
            }
        }
        .onAppear {
            router.hideNavbar = true
        }
        .onDisappear {
            router.hideNavbar = false
        }
        .sheet(isPresented: $viewModel.showProgramDetail) {
            if let program = viewModel.selectedProgram {
                ProgramDetailPopup(
                    program: program,
                    viewModel: viewModel,
                    onPlay: {
                        if let chId = program.channelId { playChannel(chId) }
                    },
                    onRecord: { toggleRecording(program) },
                    onToggleFavorite: {
                        if let chId = program.channelId {
                            Task { await viewModel.toggleChannelFavorite(channelId: chId) }
                        }
                    }
                )
                .environmentObject(theme)
                .focusSection()
            }
        }
        .task { await viewModel.loadGuide() }
    }

    private var guideHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                Text("Live TV Guide")
                    .font(.title2xl)
                    .foregroundColor(theme.colorScheme.onBackground)

                Button(action: {
                    router.reset()
                }) {
                    Label("Home", systemImage: "house.fill")
                }
                .buttonStyle(GuideNavButtonStyle(theme: theme))
            }

            Spacer()

            HStack(spacing: SpaceTokens.spaceMd) {
                Button(action: { viewModel.navigateDay(forward: false) }) {
                    Label("Previous Day", systemImage: "chevron.left")
                }
                .buttonStyle(GuideNavButtonStyle(theme: theme))

                Text(guideDateLabel)
                    .font(.bodyLg)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .frame(minWidth: 160)

                Button(action: { viewModel.navigateDay(forward: true) }) {
                    Label("Next Day", systemImage: "chevron.right")
                }
                .buttonStyle(GuideNavButtonStyle(theme: theme))

                Button(action: { viewModel.goToToday() }) {
                    Text("Today")
                }
                .buttonStyle(GuideNavButtonStyle(theme: theme))

                Button(action: { viewModel.toggleFavorites() }) {
                    Label(
                        viewModel.showFavoritesOnly ? "All Channels" : "Favorites",
                        systemImage: viewModel.showFavoritesOnly ? "star.fill" : "star"
                    )
                }
                .buttonStyle(GuideNavButtonStyle(
                    theme: theme,
                    isActive: viewModel.showFavoritesOnly
                ))

                Button(action: { router.navigate(to: .liveTvRecordings) }) {
                    Label("Recordings", systemImage: "recordingtape")
                }
                .buttonStyle(GuideNavButtonStyle(theme: theme))
            }
        }
        .padding(.horizontal, SpaceTokens.space3xl)
        .padding(.top, SpaceTokens.spaceLg)
        .padding(.bottom, SpaceTokens.spaceSm)
    }

    private static let guideDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private var guideDateLabel: String {
        Self.guideDateFormatter.string(from: viewModel.guideStartTime)
    }

    private var guideGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                channelColumn

                VStack(alignment: .leading, spacing: 0) {
                    timelineRow
                    programGrid
                }
            }
        }
    }

    private var channelColumn: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 32)
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredChannels) { channel in
                    ChannelHeaderCell(
                        channel: channel,
                        imageUrl: viewModel.channelImageUrl(channel),
                        isFavorite: channel.userData?.isFavorite == true,
                        onTap: { playChannel(channel.id) }
                    )
                    .environmentObject(theme)
                    .frame(height: LiveTvGuideViewModel.rowHeight)
                }
            }
        }
        .frame(width: LiveTvGuideViewModel.channelHeaderWidth)
    }

    private var programGrid: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.filteredChannels) { channel in
                programRow(for: channel)
                    .frame(height: LiveTvGuideViewModel.rowHeight)
            }
        }
    }

    private var timelineRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(viewModel.timeSlots) { slot in
                    Text(slot.label)
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                        .frame(width: 30 * LiveTvGuideViewModel.pixelsPerMinute, alignment: .leading)
                        .padding(.leading, SpaceTokens.spaceXs)
                }
            }
            .frame(height: 32)
        }
    }

    private func programRow(for channel: ServerItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            let programs = viewModel.programs(for: channel.id)
            ZStack(alignment: .leading) {
                let totalWidth = CGFloat(LiveTvGuideViewModel.visibleHours * 60) * LiveTvGuideViewModel.pixelsPerMinute
                Color.clear.frame(width: totalWidth, height: LiveTvGuideViewModel.rowHeight)

                if programs.isEmpty {
                    noProgramDataCell(width: totalWidth)
                } else {
                    ForEach(programs) { program in
                        let width = viewModel.programWidth(for: program)
                        let offset = viewModel.programOffset(for: program)

                        ProgramGridCell(
                            program: program,
                            width: width,
                            isAiring: viewModel.isCurrentlyAiring(program),
                            categoryColor: viewModel.programCategoryColor(program),
                            hasTimer: program.timerId != nil,
                            showHD: container.userPreferences[UserPreferences.liveTvShowHDIndicator] && program.isHD == true,
                            showNew: container.userPreferences[UserPreferences.liveTvShowNewIndicator] && program.isPremiere == true,
                            showRepeat: container.userPreferences[UserPreferences.liveTvShowRepeatIndicator] && program.isRepeat == true,
                            showLive: container.userPreferences[UserPreferences.liveTvShowLiveIndicator] && program.isLive == true,
                            onSelect: { viewModel.selectProgram(program) }
                        )
                        .environmentObject(theme)
                        .offset(x: offset)
                    }
                }
            }
        }
    }

    private func noProgramDataCell(width: CGFloat) -> some View {
        HStack(spacing: SpaceTokens.spaceXs) {
            Image(systemName: "tv.slash")
                .font(.system(size: 10))
            Text("No program information available")
                .font(.captionXs)
        }
        .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
        .frame(width: width, height: LiveTvGuideViewModel.rowHeight)
        .background(theme.colorScheme.surface.opacity(0.15))
        .overlay(
            Rectangle()
                .stroke(theme.colorScheme.surface.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var loadingView: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            ProgressView()
                .tint(theme.accent)
            Text("Loading guide data…")
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(theme.colorScheme.recording)
            Text("Failed to load guide")
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground)
            Text(message)
                .font(.bodySm)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.loadGuide() } }
                .buttonStyle(GuideNavButtonStyle(theme: theme))
        }
        .padding()
    }

    private func playChannel(_ channelId: String) {
        Task {
            guard let server = container.serverRepository.currentServer.value else { return }
            let client = container.serverClientFactory.client(for: server)
            do {
                let item = try await client.userLibraryApi.getItem(itemId: channelId)
                await container.playbackCoordinator.startVideoPlayback(items: [item])
                router.navigate(to: .liveTvPlayer(channelId: channelId))
            } catch {
                viewModel.error = "Failed to start playback: \(error.localizedDescription)"
            }
        }
    }

    private func toggleRecording(_ program: ServerItem) {
        Task {
            guard let server = container.serverRepository.currentServer.value else { return }
            let client = container.serverClientFactory.client(for: server)
            do {
                if let timerId = program.timerId {
                    try await client.liveTvApi.cancelTimer(timerId: timerId)
                } else {
                    let timer = LiveTvTimerInfo(
                        id: "",
                        name: program.name,
                        channelId: program.channelId,
                        channelName: program.channelName,
                        programId: program.id,
                        seriesTimerId: nil,
                        startDate: program.startDate ?? program.premiereDate,
                        endDate: program.endDate,
                        prePaddingSeconds: 60,
                        postPaddingSeconds: 60,
                        status: nil
                    )
                    try await client.liveTvApi.createTimer(timer)
                }
                await viewModel.loadGuide()
            } catch {
                viewModel.error = "Recording action failed: \(error.localizedDescription)"
            }
        }
    }
}

struct ChannelHeaderCell: View {
    let channel: ServerItem
    let imageUrl: String?
    let isFavorite: Bool
    let onTap: () -> Void
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SpaceTokens.spaceSm) {
                if let url = imageUrl, let imageURL = URL(string: url) {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.extraSmall))
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: SpaceTokens.space2xs) {
                        if let number = channel.channelNumber {
                            Text(number)
                                .font(.captionXs)
                                .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
                        }
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2xs)
                                .foregroundColor(.colorYellow400)
                        }
                    }
                    Text(channel.name)
                        .font(.bodySm)
                        .foregroundColor(theme.colorScheme.onBackground)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .frame(maxHeight: .infinity)
            .background(theme.colorScheme.surface.opacity(0.2))
            .overlay(
                Rectangle()
                    .stroke(theme.colorScheme.surface.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(ChannelCellButtonStyle(accent: theme.accent))
    }
}

struct ProgramGridCell: View {
    let program: ServerItem
    let width: CGFloat
    let isAiring: Bool
    let categoryColor: Color?
    let hasTimer: Bool
    let showHD: Bool
    let showNew: Bool
    let showRepeat: Bool
    let showLive: Bool
    let onSelect: () -> Void
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SpaceTokens.space2xs) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(program.name)
                        .font(.captionXs)
                        .fontWeight(isAiring ? .semibold : .regular)
                        .foregroundColor(theme.colorScheme.onBackground)
                        .lineLimit(1)

                    if let ep = episodeLabel {
                        Text(ep)
                            .font(.caption2xs)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                indicatorIcons
            }
            .padding(.horizontal, SpaceTokens.spaceXs)
            .frame(width: width, height: LiveTvGuideViewModel.rowHeight)
            .background(cellBackground)
            .overlay(cellBorder)
        }
        .buttonStyle(ProgramCellButtonStyle(accent: theme.accent))
    }

    private var episodeLabel: String? {
        if let sn = program.parentIndexNumber, let en = program.indexNumber {
            return "S\(sn)E\(en)"
        }
        return nil
    }

    @ViewBuilder
    private var indicatorIcons: some View {
        HStack(spacing: 2) {
            if hasTimer {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(theme.colorScheme.recording)
            }
            if showHD {
                Text("HD")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
            }
            if showNew {
                Text("NEW")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.colorCyan500)
            }
            if showRepeat {
                Text("R")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
            }
            if showLive {
                Text("LIVE")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(theme.colorScheme.recording)
            }
        }
    }

    private var cellBackground: some View {
        Group {
            if isAiring {
                (categoryColor ?? theme.accent).opacity(0.2)
            } else {
                categoryColor ?? theme.colorScheme.surface.opacity(0.15)
            }
        }
    }

    private var cellBorder: some View {
        Rectangle()
            .stroke(theme.colorScheme.surface.opacity(0.3), lineWidth: 0.5)
    }
}

struct ChannelCellButtonStyle: ButtonStyle {
    let accent: Color
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isFocused ? accent : .clear)
                    .frame(width: 3)
            }
            .background(isFocused ? accent.opacity(0.12) : .clear)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct ProgramCellButtonStyle: ButtonStyle {
    let accent: Color
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .shadow(color: isFocused ? accent.opacity(0.4) : .clear, radius: 4)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct ProgramDetailPopup: View {
    let program: ServerItem
    let viewModel: LiveTvGuideViewModel
    let onPlay: () -> Void
    let onRecord: () -> Void
    let onToggleFavorite: () -> Void
    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
            HStack {
                VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                    Text(program.name)
                        .font(.title2xl)
                        .foregroundColor(theme.colorScheme.onBackground)

                    if let channelName = program.channelName {
                        Text(channelName)
                            .font(.bodyMd)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    }
                }
                Spacer()
            }

            timeInfo

            if let overview = program.overview, !overview.isEmpty {
                Text(overview)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(6)
            }

            metadataBadges

            HStack(spacing: SpaceTokens.spaceMd) {
                if viewModel.isCurrentlyAiring(program) {
                    Button(action: { dismiss(); onPlay() }) {
                        Label("Watch", systemImage: "play.fill")
                    }
                    .buttonStyle(GuidePrimaryButtonStyle(theme: theme))
                }

                Button(action: { dismiss(); onRecord() }) {
                    Label(
                        program.timerId != nil ? "Cancel Recording" : "Record",
                        systemImage: program.timerId != nil ? "record.circle.fill" : "record.circle"
                    )
                }
                .buttonStyle(GuideSecondaryButtonStyle(theme: theme))

                Button(action: { dismiss(); onToggleFavorite() }) {
                    Label(
                        viewModel.isChannelFavorite(program.channelId) ? "Unfavorite Channel" : "Favorite Channel",
                        systemImage: viewModel.isChannelFavorite(program.channelId) ? "star.fill" : "star"
                    )
                }
                .buttonStyle(GuideSecondaryButtonStyle(theme: theme))

                Button("Close") { dismiss() }
                    .buttonStyle(GuideSecondaryButtonStyle(theme: theme))
            }
        }
        .padding(SpaceTokens.space3xl)
        .background(theme.colorScheme.surface)
    }

    private var timeInfo: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            if let start = program.startDate ?? program.premiereDate {
                HStack(spacing: SpaceTokens.spaceXs) {
                    Image(systemName: "clock")
                        .font(.captionXs)
                    Text(formatTime(start))
                        .font(.bodySm)
                }
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
            }

            if let start = program.startDate ?? program.premiereDate, let end = program.endDate {
                let minutes = Int(end.timeIntervalSince(start) / 60)
                Text("\(minutes) min")
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            }

            if viewModel.isCurrentlyAiring(program) {
                Text("ON NOW")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, SpaceTokens.spaceSm)
                    .padding(.vertical, 2)
                    .background(theme.accent.opacity(0.3))
                    .foregroundColor(theme.accent)
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var metadataBadges: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            if program.isMovie == true { badge("Movie") }
            if program.isSeries == true { badge("Series") }
            if program.isNews == true { badge("News") }
            if program.isSports == true { badge("Sports") }
            if program.isKids == true { badge("Kids") }
            if program.isPremiere == true { badge("Premiere", highlight: true) }
            if program.isHD == true { badge("HD") }
            if program.isLive == true { badge("Live", highlight: true) }
            if program.isRepeat == true { badge("Repeat") }
            if let rating = program.officialRating {
                badge(rating)
            }
        }
    }

    private func badge(_ text: String, highlight: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, 2)
            .background(highlight ? theme.accent.opacity(0.2) : theme.colorScheme.surface.opacity(0.5))
            .foregroundColor(highlight ? theme.accent : theme.colorScheme.onBackground.opacity(0.7))
            .clipShape(Capsule())
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}

struct GuideNavButtonStyle: ButtonStyle {
    let theme: MoonfinTheme
    var isActive: Bool = false
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodySm)
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceXs)
            .background(
                isFocused
                    ? theme.accent
                    : (isActive ? theme.accent.opacity(0.7) : theme.colorScheme.button)
            )
            .foregroundColor(isFocused || isActive ? .white : theme.colorScheme.onButton)
            .clipShape(Capsule())
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct GuidePrimaryButtonStyle: ButtonStyle {
    let theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMd)
            .fontWeight(.semibold)
            .padding(.horizontal, SpaceTokens.spaceLg)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(isFocused ? theme.accent : theme.accent.opacity(0.6))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct GuideSecondaryButtonStyle: ButtonStyle {
    let theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMd)
            .padding(.horizontal, SpaceTokens.spaceLg)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(isFocused ? theme.accent : theme.colorScheme.button)
            .foregroundColor(isFocused ? .white : theme.colorScheme.onButton)
            .clipShape(Capsule())
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
