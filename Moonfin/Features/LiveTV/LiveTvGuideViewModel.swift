import SwiftUI

struct GuideTimeSlot: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
}

enum GuideQuickFilter: CaseIterable {
    case all
    case movies
    case series
    case sports
    case news
    case kids
    case premiere
    case favorites
}

@MainActor
final class LiveTvGuideViewModel: ObservableObject {

    @Published private(set) var channels: [ServerItem] = []
    @Published private(set) var programsByChannel: [String: [ServerItem]] = [:]
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var selectedProgram: ServerItem?
    @Published private(set) var guideStartTime: Date = Date()
    @Published private(set) var guideEndTime: Date = Date()
    @Published private(set) var guideWindowHours: Int = LiveTvGuideViewModel.defaultGuideHours
    @Published private(set) var timeSlots: [GuideTimeSlot] = []
    @Published var selectedDate: Date = Date()
    @Published var showProgramDetail = false
    @Published var quickFilter: GuideQuickFilter = .all

    static let defaultGuideHours = 9
    static let minGuideHours = 3
    static let maxGuideHours = 12
    static let pixelsPerMinute: CGFloat = 7
    static let channelHeaderWidth: CGFloat = 200
    static let rowHeight: CGFloat = 55

    private let container: AppContainer
    private var allChannels: [ServerItem] = []

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    private var preferences: UserPreferences { container.userPreferences }

    var filteredChannels: [ServerItem] {
        let base = (quickFilter == .favorites)
            ? channels.filter { $0.userData?.isFavorite == true }
            : channels

        let quickFiltered: [ServerItem]
        switch quickFilter {
        case .all, .favorites:
            quickFiltered = base
        default:
            quickFiltered = base.filter { channel in
                let programs = programsByChannel[channel.id] ?? []
                return programs.contains(where: matchesQuickFilter)
            }
        }

        guard hasProgramTypeFiltersEnabled else { return quickFiltered }
        return quickFiltered.filter { channel in
            let programs = programsByChannel[channel.id] ?? []
            return programs.contains(where: matchesProgramTypeFilter)
        }
    }

    init(container: AppContainer) {
        self.container = container
    }

    func loadGuide(windowHours: Int? = nil, resetWindowToSelectedDate: Bool = true) async {
        guard !isLoading else { return }
        guard let client else {
            error = Strings.liveTvNoServerConnection
            return
        }
        isLoading = true
        error = nil

        if let windowHours {
            guideWindowHours = min(max(windowHours, Self.minGuideHours), Self.maxGuideHours)
        }

        do {
            if resetWindowToSelectedDate {
                let cal = Calendar.current
                let now = selectedDate
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
                let roundedMinute = ((comps.minute ?? 0) / 30) * 30
                var startComps = comps
                startComps.minute = roundedMinute
                startComps.second = 0
                let start = cal.date(from: startComps) ?? now
                guideStartTime = start
                guideEndTime = cal.date(byAdding: .hour, value: guideWindowHours, to: start) ?? start
            } else if guideEndTime <= guideStartTime {
                let cal = Calendar.current
                guideEndTime = cal.date(byAdding: .hour, value: guideWindowHours, to: guideStartTime) ?? guideStartTime
            }

            buildTimeSlots()

            let sortByLastPlayed = preferences[UserPreferences.liveTvChannelOrder] == .lastPlayed
            let sortBy = sortByLastPlayed ? "DatePlayed" : "SortName"
            let sortOrder = sortByLastPlayed ? "Descending" : "Ascending"

            let channelsResult = try await client.liveTvApi.getChannels(
                userId: client.userId,
                startIndex: nil,
                limit: nil,
                sortBy: sortBy,
                sortOrder: sortOrder,
                isFavorite: nil,
                addCurrentProgram: true
            )

            allChannels = channelsResult.items

            if preferences[UserPreferences.liveTvFavsAtTop] {
                let favs = allChannels.filter { $0.userData?.isFavorite == true }
                let rest = allChannels.filter { $0.userData?.isFavorite != true }
                allChannels = favs + rest
            }

            channels = allChannels

            let channelIds = channels.map(\.id)
            let batchSize = 200
            var allPrograms: [String: [ServerItem]] = [:]

            for batchStart in stride(from: 0, to: channelIds.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, channelIds.count)
                let batch = Array(channelIds[batchStart..<batchEnd])

                let programsResult = try await client.liveTvApi.getPrograms(
                    channelIds: batch,
                    userId: client.userId,
                    startIndex: nil,
                    limit: nil,
                    minStartDate: nil,
                    maxStartDate: guideEndTime,
                    minEndDate: guideStartTime,
                    sortBy: "StartDate"
                )

                for program in programsResult.items {
                    guard let chId = program.channelId else { continue }
                    allPrograms[chId, default: []].append(program)
                }
            }

            programsByChannel = allPrograms
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func goToNow() {
        selectedDate = Date()
        Task { await loadGuide(resetWindowToSelectedDate: true) }
    }

    func shiftWindow(hours: Int) {
        let cal = Calendar.current
        guideStartTime = cal.date(byAdding: .hour, value: hours, to: guideStartTime) ?? guideStartTime
        guideEndTime = cal.date(byAdding: .hour, value: guideWindowHours, to: guideStartTime) ?? guideStartTime
        selectedDate = guideStartTime
        buildTimeSlots()
        Task { await loadGuide(resetWindowToSelectedDate: false) }
    }

    func isChannelFavorite(_ channelId: String?) -> Bool {
        guard let channelId else { return false }
        return channels.first(where: { $0.id == channelId })?.userData?.isFavorite == true
    }

    func toggleChannelFavorite(channelId: String) async {
        guard let client else { return }
        guard let userId = client.userId else { return }
        let isFav = isChannelFavorite(channelId)
        do {
            if isFav {
                _ = try await client.userLibraryApi.unmarkFavorite(itemId: channelId, userId: userId)
            } else {
                _ = try await client.userLibraryApi.markFavorite(itemId: channelId, userId: userId)
            }
            await loadGuide()
        } catch {
            self.error = Strings.liveTvFailedToUpdateFavorite(error.localizedDescription)
        }
    }

    func selectProgram(_ program: ServerItem) {
        selectedProgram = program
        showProgramDetail = true
    }

    func programs(for channelId: String) -> [ServerItem] {
        let basePrograms = programsByChannel[channelId] ?? []
        let quickPrograms: [ServerItem]
        switch quickFilter {
        case .all, .favorites:
            quickPrograms = basePrograms
        default:
            quickPrograms = basePrograms.filter(matchesQuickFilter)
        }

        guard hasProgramTypeFiltersEnabled else { return quickPrograms }
        return quickPrograms.filter(matchesProgramTypeFilter)
    }

    func programWidth(for program: ServerItem) -> CGFloat {
        let start = max(program.startDate ?? program.premiereDate ?? guideStartTime, guideStartTime)
        let end = min(program.endDate ?? guideEndTime, guideEndTime)
        let minutes = max(end.timeIntervalSince(start) / 60, 0)
        return max(CGFloat(minutes) * Self.pixelsPerMinute, 1)
    }

    func programOffset(for program: ServerItem) -> CGFloat {
        let start = max(program.startDate ?? program.premiereDate ?? guideStartTime, guideStartTime)
        let minutes = start.timeIntervalSince(guideStartTime) / 60
        return CGFloat(minutes) * Self.pixelsPerMinute
    }

    func isCurrentlyAiring(_ program: ServerItem) -> Bool {
        let now = Date()
        let start = program.startDate ?? program.premiereDate ?? now
        let end = program.endDate ?? now
        return start <= now && end >= now
    }

    func channelImageUrl(_ channel: ServerItem) -> String? {
        guard let tag = channel.imageTags?["Primary"] else { return nil }
        return client?.imageApi.getItemImageUrl(
            itemId: channel.id, imageType: .primary, maxWidth: 100, maxHeight: 100, tag: tag
        )
    }

    func programCategoryColor(_ program: ServerItem) -> Color? {
        guard preferences[UserPreferences.liveTvColorCodeGuide] else { return nil }
        if program.isMovie == true { return .colorCyan500.opacity(0.3) }
        if program.isSports == true { return .colorGreen400.opacity(0.3) }
        if program.isNews == true { return .colorYellow400.opacity(0.3) }
        if program.isKids == true { return .colorOrange400.opacity(0.3) }
        if program.isSeries == true { return .colorPurple400.opacity(0.3) }
        return nil
    }

    private static let timeSlotFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private func buildTimeSlots() {
        let cal = Calendar.current
        var slots: [GuideTimeSlot] = []
        var current = guideStartTime
        while current < guideEndTime {
            slots.append(GuideTimeSlot(date: current, label: Self.timeSlotFormatter.string(from: current)))
            current = cal.date(byAdding: .minute, value: 30, to: current) ?? current
        }
        timeSlots = slots
    }

    private var hasProgramTypeFiltersEnabled: Bool {
        preferences[UserPreferences.liveTvFilterMovies]
            || preferences[UserPreferences.liveTvFilterSeries]
            || preferences[UserPreferences.liveTvFilterNews]
            || preferences[UserPreferences.liveTvFilterKids]
            || preferences[UserPreferences.liveTvFilterSports]
            || preferences[UserPreferences.liveTvFilterPremiere]
    }

    private func matchesProgramTypeFilter(_ program: ServerItem) -> Bool {
        var matched = false
        if preferences[UserPreferences.liveTvFilterMovies] {
            matched = matched || (program.isMovie == true)
        }
        if preferences[UserPreferences.liveTvFilterSeries] {
            matched = matched || (program.isSeries == true)
        }
        if preferences[UserPreferences.liveTvFilterNews] {
            matched = matched || (program.isNews == true)
        }
        if preferences[UserPreferences.liveTvFilterKids] {
            matched = matched || (program.isKids == true)
        }
        if preferences[UserPreferences.liveTvFilterSports] {
            matched = matched || (program.isSports == true)
        }
        if preferences[UserPreferences.liveTvFilterPremiere] {
            matched = matched || (program.isPremiere == true)
        }
        return matched
    }

    private func matchesQuickFilter(_ program: ServerItem) -> Bool {
        switch quickFilter {
        case .all, .favorites:
            return true
        case .movies:
            return program.isMovie == true
        case .series:
            return program.isSeries == true
        case .sports:
            return program.isSports == true
        case .news:
            return program.isNews == true
        case .kids:
            return program.isKids == true
        case .premiere:
            return program.isPremiere == true
        }
    }

}
