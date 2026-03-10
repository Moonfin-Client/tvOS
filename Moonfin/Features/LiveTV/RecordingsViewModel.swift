import SwiftUI

enum RecordingsTab {
    case recordings
    case scheduled
    case series
}

enum RecordingFilter: String, CaseIterable {
    case all = "All"
    case past24h = "Past 24h"
    case pastWeek = "Past Week"
}

@MainActor
final class RecordingsViewModel: ObservableObject {

    @Published private(set) var recordings: [ServerItem] = []
    @Published private(set) var timers: [LiveTvTimerInfo] = []
    @Published private(set) var seriesTimers: [LiveTvSeriesTimerInfo] = []
    @Published private(set) var isLoading = false
    @Published var activeTab: RecordingsTab = .recordings
    @Published var recordingFilter: RecordingFilter = .all
    @Published var selectedRecording: ServerItem?
    @Published var selectedTimer: LiveTvTimerInfo?
    @Published var selectedSeriesTimer: LiveTvSeriesTimerInfo?
    @Published var error: String?

    private let container: AppContainer

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    init(container: AppContainer) {
        self.container = container
    }

    var filteredRecordings: [ServerItem] {
        switch recordingFilter {
        case .all:
            return recordings
        case .past24h:
            let cutoff = Date().addingTimeInterval(-86400)
            return recordings.filter { ($0.endDate ?? .distantPast) >= cutoff }
        case .pastWeek:
            let cutoff = Date().addingTimeInterval(-604800)
            return recordings.filter { ($0.endDate ?? .distantPast) >= cutoff }
        }
    }

    func loadData() async {
        guard let client else {
            error = "No server connection"
            return
        }
        isLoading = true
        error = nil

        do {
            async let recordingsResult = client.liveTvApi.getRecordings(
                channelId: nil, seriesTimerId: nil, startIndex: nil, limit: nil
            )
            async let timersResult = client.liveTvApi.getTimers(
                channelId: nil, seriesTimerId: nil
            )
            async let seriesTimersResult = client.liveTvApi.getSeriesTimers(
                sortBy: nil, startIndex: nil, limit: nil
            )

            let (recs, tims, sTims) = try await (recordingsResult, timersResult, seriesTimersResult)
            recordings = recs.items
            timers = tims
            seriesTimers = sTims
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func deleteRecording(_ recording: ServerItem) async {
        guard let client else { return }

        do {
            try await client.liveTvApi.deleteRecording(recordingId: recording.id)
            recordings.removeAll { $0.id == recording.id }
            selectedRecording = nil
        } catch {
            self.error = "Failed to delete recording: \(error.localizedDescription)"
        }
    }

    func cancelTimer(_ timer: LiveTvTimerInfo) async {
        guard let client else { return }

        do {
            try await client.liveTvApi.cancelTimer(timerId: timer.id)
            timers.removeAll { $0.id == timer.id }
            selectedTimer = nil
        } catch {
            self.error = "Failed to cancel recording: \(error.localizedDescription)"
        }
    }

    func cancelSeriesTimer(_ seriesTimer: LiveTvSeriesTimerInfo) async {
        guard let client else { return }

        do {
            try await client.liveTvApi.cancelSeriesTimer(timerId: seriesTimer.id)
            seriesTimers.removeAll { $0.id == seriesTimer.id }
            selectedSeriesTimer = nil
        } catch {
            self.error = "Failed to cancel series recording: \(error.localizedDescription)"
        }
    }

    func recordingImageUrl(_ recording: ServerItem) -> String? {
        guard let tag = recording.imageTags?["Primary"] else { return nil }
        return client?.imageApi.getItemImageUrl(
            itemId: recording.id, imageType: .primary, maxWidth: 300, maxHeight: 450, tag: tag
        )
    }

    func timerImageUrl(_ timer: LiveTvTimerInfo) -> String? {
        guard let programId = timer.programId else { return nil }
        return client?.imageApi.getItemImageUrl(
            itemId: programId, imageType: .primary, maxWidth: 300, maxHeight: 450, tag: nil
        )
    }

    func formatDuration(_ ticks: Int64) -> String {
        let totalMinutes = Int(ticks / 600_000_000)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static let scheduledDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let scheduledTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    func formatScheduledTime(_ startDate: Date?, _ endDate: Date?) -> String {
        guard let start = startDate else { return "" }
        let datePart = Self.scheduledDateFormatter.string(from: start)
        let startTime = Self.scheduledTimeFormatter.string(from: start)
        if let end = endDate {
            let endTime = Self.scheduledTimeFormatter.string(from: end)
            return "\(datePart) \(startTime) - \(endTime)"
        }
        return "\(datePart) \(startTime)"
    }
}
