import SwiftUI

struct GuideTimeSlot: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
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
    @Published private(set) var timeSlots: [GuideTimeSlot] = []
    @Published var selectedDate: Date = Date()
    @Published var showProgramDetail = false
    @Published var showFavoritesOnly = false

    static let visibleHours = 9
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
        if showFavoritesOnly {
            return channels.filter { $0.userData?.isFavorite == true }
        }
        return channels
    }

    init(container: AppContainer) {
        self.container = container
    }

    func loadGuide() async {
        guard !isLoading else { return }
        guard let client else {
            error = "No server connection"
            return
        }
        isLoading = true
        error = nil

        do {
            let cal = Calendar.current
            let now = selectedDate
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
            let roundedMinute = ((comps.minute ?? 0) / 30) * 30
            var startComps = comps
            startComps.minute = roundedMinute
            startComps.second = 0
            let start = cal.date(from: startComps) ?? now
            guideStartTime = start
            guideEndTime = cal.date(byAdding: .hour, value: Self.visibleHours, to: start) ?? start

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

    func navigateDay(forward: Bool) {
        let cal = Calendar.current
        let days = forward ? 1 : -1
        selectedDate = cal.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
        Task { await loadGuide() }
    }

    func goToToday() {
        selectedDate = Date()
        Task { await loadGuide() }
    }

    func toggleFavorites() {
        showFavoritesOnly.toggle()
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
            self.error = "Failed to update favorite: \(error.localizedDescription)"
        }
    }

    func selectProgram(_ program: ServerItem) {
        selectedProgram = program
        showProgramDetail = true
    }

    func programs(for channelId: String) -> [ServerItem] {
        programsByChannel[channelId] ?? []
    }

    func programWidth(for program: ServerItem) -> CGFloat {
        let start = max(program.startDate ?? program.premiereDate ?? guideStartTime, guideStartTime)
        let end = min(program.endDate ?? guideEndTime, guideEndTime)
        let minutes = end.timeIntervalSince(start) / 60
        return max(CGFloat(minutes) * Self.pixelsPerMinute, 40)
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

}
