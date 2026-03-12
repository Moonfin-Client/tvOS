import SwiftUI

struct RecordingsView: View {
    @StateObject private var viewModel: RecordingsViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    private let container: AppContainer
    private let initialTab: RecordingsTab

    init(container: AppContainer, initialTab: RecordingsTab = .recordings) {
        self.container = container
        self.initialTab = initialTab
        _viewModel = StateObject(wrappedValue: RecordingsViewModel(container: container))
    }

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.recordings.isEmpty && viewModel.timers.isEmpty && viewModel.seriesTimers.isEmpty {
                loadingView
            } else if let error = viewModel.error,
                      viewModel.recordings.isEmpty && viewModel.timers.isEmpty && viewModel.seriesTimers.isEmpty {
                errorView(error)
            } else {
                VStack(spacing: 0) {
                    header
                    content
                }
            }
        }
        .sheet(item: $viewModel.selectedRecording) { recording in
            RecordingDetailPopup(
                recording: recording,
                viewModel: viewModel,
                onPlay: { playRecording(recording) },
                onDelete: { Task { await viewModel.deleteRecording(recording) } }
            )
            .environmentObject(theme)
            .focusSection()
        }
        .sheet(item: $viewModel.selectedTimer) { timer in
            TimerDetailPopup(
                timer: timer,
                viewModel: viewModel,
                onCancel: { Task { await viewModel.cancelTimer(timer) } }
            )
            .environmentObject(theme)
            .focusSection()
        }
        .sheet(item: $viewModel.selectedSeriesTimer) { seriesTimer in
            SeriesTimerDetailPopup(
                seriesTimer: seriesTimer,
                viewModel: viewModel,
                onCancel: { Task { await viewModel.cancelSeriesTimer(seriesTimer) } }
            )
            .environmentObject(theme)
            .focusSection()
        }
        .task {
            viewModel.activeTab = initialTab
            await viewModel.loadData()
        }
    }

    private var header: some View {
        HStack {
            Text("Recordings")
                .font(.title2xl)
                .foregroundColor(theme.colorScheme.onBackground)

            Spacer()

            HStack(spacing: SpaceTokens.spaceMd) {
                Button(action: { viewModel.activeTab = .recordings }) {
                    Text("Recordings (\(viewModel.filteredRecordings.count))")
                }
                .buttonStyle(GuideNavButtonStyle(
                    theme: theme,
                    isActive: viewModel.activeTab == .recordings
                ))

                Button(action: { viewModel.activeTab = .scheduled }) {
                    Text("Scheduled (\(viewModel.timers.count))")
                }
                .buttonStyle(GuideNavButtonStyle(
                    theme: theme,
                    isActive: viewModel.activeTab == .scheduled
                ))

                Button(action: { viewModel.activeTab = .series }) {
                    Text("Series (\(viewModel.seriesTimers.count))")
                }
                .buttonStyle(GuideNavButtonStyle(
                    theme: theme,
                    isActive: viewModel.activeTab == .series
                ))

                Button(action: { router.navigate(to: .liveTvGuide) }) {
                    Label("Guide", systemImage: "tv")
                }
                .buttonStyle(GuideNavButtonStyle(theme: theme))
            }
        }
        .padding(.horizontal, SpaceTokens.space3xl)
        .padding(.top, SpaceTokens.spaceLg)
        .padding(.bottom, SpaceTokens.spaceMd)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch viewModel.activeTab {
                case .recordings:
                    recordingsGrid
                case .scheduled:
                    scheduledGrid
                case .series:
                    seriesGrid
                }
            }
            .padding(.horizontal, SpaceTokens.space3xl)
            .padding(.bottom, SpaceTokens.space3xl)
        }
    }

    private var recordingsGrid: some View {
        Group {
            filterBar
            if viewModel.filteredRecordings.isEmpty {
                emptyState("No recordings found")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 300), spacing: SpaceTokens.spaceLg)],
                    spacing: SpaceTokens.spaceLg
                ) {
                    ForEach(viewModel.filteredRecordings) { recording in
                        RecordingCard(
                            recording: recording,
                            imageUrl: viewModel.recordingImageUrl(recording),
                            duration: recording.runTimeTicks.map { viewModel.formatDuration($0) }
                        ) {
                            viewModel.selectedRecording = recording
                        }
                        .environmentObject(theme)
                    }
                }
            }
        }
    }

    private var scheduledGrid: some View {
        Group {
            if viewModel.timers.isEmpty {
                emptyState("No scheduled recordings")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 300), spacing: SpaceTokens.spaceLg)],
                    spacing: SpaceTokens.spaceLg
                ) {
                    ForEach(viewModel.timers, id: \.id) { timer in
                        TimerCard(
                            timer: timer,
                            imageUrl: viewModel.timerImageUrl(timer),
                            scheduledTime: viewModel.formatScheduledTime(timer.startDate, timer.endDate)
                        ) {
                            viewModel.selectedTimer = timer
                        }
                        .environmentObject(theme)
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            ForEach(RecordingFilter.allCases, id: \.self) { filter in
                Button(action: { viewModel.recordingFilter = filter }) {
                    Text(filter.rawValue)
                }
                .buttonStyle(GuideNavButtonStyle(
                    theme: theme,
                    isActive: viewModel.recordingFilter == filter
                ))
            }
            Spacer()
        }
        .padding(.bottom, SpaceTokens.spaceSm)
    }

    private var seriesGrid: some View {
        Group {
            if viewModel.seriesTimers.isEmpty {
                emptyState("No series recordings")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 300), spacing: SpaceTokens.spaceLg)],
                    spacing: SpaceTokens.spaceLg
                ) {
                    ForEach(viewModel.seriesTimers, id: \.id) { seriesTimer in
                        SeriesTimerCard(seriesTimer: seriesTimer) {
                            viewModel.selectedSeriesTimer = seriesTimer
                        }
                        .environmentObject(theme)
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Image(systemName: "recordingtape")
                .font(.system(size: 40))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.3))
            Text(message)
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var loadingView: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            ProgressView()
                .tint(theme.accent)
            Text("Loading recordings…")
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(theme.colorScheme.recording)
            Text("Failed to load recordings")
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground)
            Text(message)
                .font(.bodySm)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.loadData() } }
                .buttonStyle(GuideNavButtonStyle(theme: theme))
        }
        .padding()
    }

    private func playRecording(_ recording: ServerItem) {
        Task {
            await container.playbackCoordinator.startVideoPlayback(items: [recording])
            router.navigate(to: .videoPlayer)
        }
    }
}

struct RecordingCard: View {
    let recording: ServerItem
    let imageUrl: String?
    let duration: String?
    let onSelect: () -> Void
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                CardImageSection(url: imageUrl, placeholderIcon: "tv")
                    .environmentObject(theme)
                infoSection
            }
            .background(theme.colorScheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.medium))
        }
        .buttonStyle(RecordingCardButtonStyle(accent: theme.accent))
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Text(recording.name)
                .font(.bodyMd)
                .fontWeight(.medium)
                .foregroundColor(theme.colorScheme.onBackground)
                .lineLimit(1)

            if let episodeLabel = recordingEpisodeLabel {
                Text(episodeLabel)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    .lineLimit(1)
            }

            HStack(spacing: SpaceTokens.spaceXs) {
                if let channelName = recording.channelName {
                    Text(channelName)
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
                }
                if let dur = duration {
                    Text("•")
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.3))
                    Text(dur)
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
                }
            }
        }
        .padding(SpaceTokens.spaceMd)
    }

    private var recordingEpisodeLabel: String? {
        if let sn = recording.parentIndexNumber, let en = recording.indexNumber {
            return "S\(sn)E\(en)"
        }
        return recording.seriesName
    }
}

struct TimerCard: View {
    let timer: LiveTvTimerInfo
    let imageUrl: String?
    let scheduledTime: String
    let onSelect: () -> Void
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                CardImageSection(url: imageUrl, placeholderIcon: "clock")
                    .environmentObject(theme)
                infoSection
            }
            .background(theme.colorScheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.medium))
        }
        .buttonStyle(RecordingCardButtonStyle(accent: theme.accent))
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Text(timer.name ?? "Scheduled Recording")
                .font(.bodyMd)
                .fontWeight(.medium)
                .foregroundColor(theme.colorScheme.onBackground)
                .lineLimit(1)

            if let channelName = timer.channelName {
                Text(channelName)
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
            }

            Text(scheduledTime)
                .font(.captionXs)
                .foregroundColor(theme.accent)
        }
        .padding(SpaceTokens.spaceMd)
    }
}

struct RecordingDetailPopup: View {
    let recording: ServerItem
    let viewModel: RecordingsViewModel
    let onPlay: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
            HStack {
                VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                    Text(recording.name)
                        .font(.title2xl)
                        .foregroundColor(theme.colorScheme.onBackground)

                    if let episodeLabel = recordingDetailEpisodeLabel {
                        Text(episodeLabel)
                            .font(.bodyMd)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    }
                }
                Spacer()
            }

            if let overview = recording.overview, !overview.isEmpty {
                Text(overview)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(6)
            }

            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                if let channelName = recording.channelName {
                    metadataRow("Channel", channelName, theme: theme)
                }
                if let ticks = recording.runTimeTicks {
                    metadataRow("Duration", viewModel.formatDuration(ticks), theme: theme)
                }
                if let year = recording.productionYear {
                    metadataRow("Year", "\(year)", theme: theme)
                }
                if let rating = recording.officialRating {
                    metadataRow("Rating", rating, theme: theme)
                }
            }

            HStack(spacing: SpaceTokens.spaceMd) {
                Button(action: { dismiss(); onPlay() }) {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(GuidePrimaryButtonStyle(theme: theme))

                Button(action: { dismiss(); onDelete() }) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(RecordingDangerButtonStyle(theme: theme))

                Button("Close") { dismiss() }
                    .buttonStyle(GuideSecondaryButtonStyle(theme: theme))
            }
        }
        .padding(SpaceTokens.space3xl)
        .background(theme.colorScheme.surface)
    }

    private var recordingDetailEpisodeLabel: String? {
        if let sn = recording.parentIndexNumber, let en = recording.indexNumber {
            if let seriesName = recording.seriesName {
                return "\(seriesName) — S\(sn)E\(en)"
            }
            return "S\(sn)E\(en)"
        }
        return recording.seriesName
    }
}

struct TimerDetailPopup: View {
    let timer: LiveTvTimerInfo
    let viewModel: RecordingsViewModel
    let onCancel: () -> Void
    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
            HStack {
                VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                    Text(timer.name ?? "Scheduled Recording")
                        .font(.title2xl)
                        .foregroundColor(theme.colorScheme.onBackground)

                    if let channelName = timer.channelName {
                        Text(channelName)
                            .font(.bodyMd)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                metadataRow("Scheduled", viewModel.formatScheduledTime(timer.startDate, timer.endDate), theme: theme)
                if let status = timer.status {
                    metadataRow("Status", status, theme: theme)
                }
            }

            HStack(spacing: SpaceTokens.spaceMd) {
                Button(action: { dismiss(); onCancel() }) {
                    Label("Cancel Recording", systemImage: "xmark.circle")
                }
                .buttonStyle(RecordingDangerButtonStyle(theme: theme))

                Button("Close") { dismiss() }
                    .buttonStyle(GuideSecondaryButtonStyle(theme: theme))
            }
        }
        .padding(SpaceTokens.space3xl)
        .background(theme.colorScheme.surface)
    }
}

struct SeriesTimerCard: View {
    let seriesTimer: LiveTvSeriesTimerInfo
    let onSelect: () -> Void
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                CardImageSection(url: nil, placeholderIcon: "rectangle.stack")
                    .environmentObject(theme)
                infoSection
            }
            .background(theme.colorScheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.medium))
        }
        .buttonStyle(RecordingCardButtonStyle(accent: theme.accent))
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Text(seriesTimer.name ?? "Series Recording")
                .font(.bodyMd)
                .fontWeight(.medium)
                .foregroundColor(theme.colorScheme.onBackground)
                .lineLimit(1)

            if let channelName = seriesTimer.channelName {
                Text(channelName)
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
            }

            HStack(spacing: SpaceTokens.spaceXs) {
                if seriesTimer.recordNewOnly == true {
                    Text("New only")
                        .font(.captionXs)
                        .foregroundColor(theme.accent)
                }
                if seriesTimer.recordAnyTime == true {
                    Text("Any time")
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
                }
                if seriesTimer.recordAnyChannel == true {
                    Text("Any channel")
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
                }
            }
        }
        .padding(SpaceTokens.spaceMd)
    }
}

extension LiveTvSeriesTimerInfo: Identifiable {}

struct SeriesTimerDetailPopup: View {
    let seriesTimer: LiveTvSeriesTimerInfo
    let viewModel: RecordingsViewModel
    let onCancel: () -> Void
    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
            HStack {
                VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                    Text(seriesTimer.name ?? "Series Recording")
                        .font(.title2xl)
                        .foregroundColor(theme.colorScheme.onBackground)

                    if let channelName = seriesTimer.channelName {
                        Text(channelName)
                            .font(.bodyMd)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                if seriesTimer.recordNewOnly == true {
                    metadataRow("Episodes", "New only", theme: theme)
                } else {
                    metadataRow("Episodes", "All", theme: theme)
                }
                if seriesTimer.recordAnyTime == true {
                    metadataRow("Time", "Any time", theme: theme)
                }
                if seriesTimer.recordAnyChannel == true {
                    metadataRow("Channel", "Any channel", theme: theme)
                } else if let channelName = seriesTimer.channelName {
                    metadataRow("Channel", channelName, theme: theme)
                }
                if let start = seriesTimer.startDate {
                    metadataRow("From", viewModel.formatScheduledTime(start, seriesTimer.endDate), theme: theme)
                }
            }

            HStack(spacing: SpaceTokens.spaceMd) {
                Button(action: { dismiss(); onCancel() }) {
                    Label("Cancel Series", systemImage: "xmark.circle")
                }
                .buttonStyle(RecordingDangerButtonStyle(theme: theme))

                Button("Close") { dismiss() }
                    .buttonStyle(GuideSecondaryButtonStyle(theme: theme))
            }
        }
        .padding(SpaceTokens.space3xl)
        .background(theme.colorScheme.surface)
    }
}

private func metadataRow(_ label: String, _ value: String, theme: MoonfinTheme) -> some View {
    HStack(spacing: SpaceTokens.spaceSm) {
        Text(label + ":")
            .font(.bodySm)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            .frame(width: 90, alignment: .leading)
        Text(value)
            .font(.bodySm)
            .foregroundColor(theme.colorScheme.onBackground)
    }
}

struct CardImageSection: View {
    let url: String?
    let placeholderIcon: String
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Group {
            if let url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
                .frame(height: 160)
                .clipped()
            } else {
                placeholder
                    .frame(height: 160)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            theme.colorScheme.surface.opacity(0.5)
            Image(systemName: placeholderIcon)
                .font(.system(size: 36))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.2))
        }
    }
}

struct RecordingCardButtonStyle: ButtonStyle {
    let accent: Color
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .shadow(color: isFocused ? accent.opacity(0.5) : .clear, radius: 8)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct RecordingDangerButtonStyle: ButtonStyle {
    let theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMd)
            .padding(.horizontal, SpaceTokens.spaceLg)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(isFocused ? theme.colorScheme.recording : theme.colorScheme.recording.opacity(0.6))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

extension LiveTvTimerInfo: Identifiable {}
