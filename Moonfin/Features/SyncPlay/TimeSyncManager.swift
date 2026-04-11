import Foundation

final class TimeSyncManager {
    private let client: HttpClient
    private var measurements: [Measurement] = []
    private let maxMeasurements = 8
    private var syncTask: Task<Void, Never>?
    private var isSyncing = false

    private(set) var timeOffset: Int64 = 0
    private(set) var roundTripTime: Int64 = 0
    private(set) var offsetJitterMs: Int64 = 0
    private(set) var measurementCount = 0

    var isGreedyMode: Bool { measurementCount < greedyPingCount }

    private let greedyIntervalMs: UInt64 = 1_000
    private let lowProfileIntervalMs: UInt64 = 60_000
    private let greedyPingCount = 3
    private let maxRttMs: Int64 = 5_000

    private struct Measurement {
        let offset: Int64
        let roundTripTime: Int64
        let delay: Int64
    }

    init(client: HttpClient) {
        self.client = client
    }

    func startSync() {
        guard !isSyncing else { return }
        isSyncing = true
        measurementCount = 0
        syncTask = Task { [weak self] in
            while let self, self.isSyncing, !Task.isCancelled {
                await self.performMeasurement()
                self.measurementCount += 1
                let interval = self.measurementCount < self.greedyPingCount
                    ? self.greedyIntervalMs : self.lowProfileIntervalMs
                try? await Task.sleep(nanoseconds: interval * 1_000_000)
            }
        }
    }

    func stopSync() {
        isSyncing = false
        syncTask?.cancel()
        syncTask = nil
        measurements.removeAll()
        measurementCount = 0
    }

    func syncNow() async {
        await performMeasurement()
    }

    func serverTimeToLocal(_ serverTimeMs: Int64) -> Int64 {
        serverTimeMs - timeOffset
    }

    func localTimeToServer(_ localTimeMs: Int64) -> Int64 {
        localTimeMs + timeOffset
    }

    func getServerTimeNow() -> Int64 {
        currentTimeMs() + timeOffset
    }

    private func currentTimeMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func performMeasurement() async {
        do {
            let t0 = currentTimeMs()
            let response: UtcTimeResponse = try await client.request("/GetUtcTime")
            let t3 = currentTimeMs()

            let t1 = SyncPlayUtils.parseISOToMs(response.requestReceptionTime)
            let t2 = SyncPlayUtils.parseISOToMs(response.responseTransmissionTime)

            let offset = ((t1 - t0) + (t2 - t3)) / 2
            let rtt = (t3 - t0) - (t2 - t1)
            let networkDelay = (t3 - t0) / 2

            guard rtt >= 0, rtt <= maxRttMs else { return }

            measurements.append(Measurement(offset: offset, roundTripTime: rtt, delay: networkDelay))
            while measurements.count > maxMeasurements { measurements.removeFirst() }

            if let minOffset = measurements.map({ $0.offset }).min(),
               let maxOffset = measurements.map({ $0.offset }).max() {
                offsetJitterMs = maxOffset - minOffset
            }

            if let best = measurements.min(by: { $0.delay < $1.delay }) {
                timeOffset = best.offset
                roundTripTime = best.roundTripTime
            }
        } catch { }
    }
}
