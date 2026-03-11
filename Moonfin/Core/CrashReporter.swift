import Foundation
import os

final class CrashReporter {
    static let shared = CrashReporter()
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "CrashReporter")
    private var preferences: TelemetryPreferences?

    struct CrashReport: Codable {
        let timestamp: Date
        let appVersion: String
        let osVersion: String
        let deviceModel: String
        let signal: String?
        let exception: String?
        let stackTrace: String
        let logs: String?
    }

    private init() {}

    func configure(preferences: TelemetryPreferences) {
        self.preferences = preferences
        installHandlers()
        submitPendingReports()
    }

    func updateServerEndpoint(url: String, token: String) {
        preferences?[TelemetryPreferences.crashReportUrl] = url
        preferences?[TelemetryPreferences.crashReportToken] = token
    }

    private func installHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }

        for sig: Int32 in [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP] {
            signal(sig) { sig in
                CrashReporter.shared.handleSignal(sig)
            }
        }
    }

    private func handleException(_ exception: NSException) {
        let report = CrashReport(
            timestamp: Date(),
            appVersion: AppConstants.clientVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: AppConstants.deviceName,
            signal: nil,
            exception: "\(exception.name.rawValue): \(exception.reason ?? "")",
            stackTrace: exception.callStackSymbols.joined(separator: "\n"),
            logs: collectLogs()
        )
        persistReport(report)
    }

    private func handleSignal(_ sig: Int32) {
        let signalName: String
        switch sig {
        case SIGABRT: signalName = "SIGABRT"
        case SIGBUS: signalName = "SIGBUS"
        case SIGFPE: signalName = "SIGFPE"
        case SIGILL: signalName = "SIGILL"
        case SIGSEGV: signalName = "SIGSEGV"
        case SIGTRAP: signalName = "SIGTRAP"
        default: signalName = "SIGNAL(\(sig))"
        }

        let symbols = Thread.callStackSymbols
        let report = CrashReport(
            timestamp: Date(),
            appVersion: AppConstants.clientVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: AppConstants.deviceName,
            signal: signalName,
            exception: nil,
            stackTrace: symbols.joined(separator: "\n"),
            logs: nil
        )
        persistReport(report)

        Darwin.signal(sig, SIG_DFL)
        Darwin.raise(sig)
    }

    private func persistReport(_ report: CrashReport) {
        guard let data = try? JSONEncoder().encode(report),
              let dir = crashReportsDirectory() else { return }
        let file = dir.appendingPathComponent("\(UUID().uuidString).json")
        try? data.write(to: file)
    }

    private func crashReportsDirectory() -> URL? {
        guard let support = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("crash_reports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func submitPendingReports() {
        guard let prefs = preferences,
              prefs[TelemetryPreferences.crashReportEnabled] else { return }

        let urlString = prefs[TelemetryPreferences.crashReportUrl]
        let token = prefs[TelemetryPreferences.crashReportToken]
        guard !urlString.isEmpty, !token.isEmpty, let url = URL(string: urlString) else { return }

        guard let dir = crashReportsDirectory() else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let report = try? JSONDecoder().decode(CrashReport.self, from: data) else {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            Task {
                let success = await submitReport(report, to: url, token: token)
                if success {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    private func submitReport(_ report: CrashReport, to url: URL, token: String) async -> Bool {
        let markdown = formatReportMarkdown(report)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "MediaBrowser Token=\"\(token)\"",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = markdown.data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                logger.info("Crash report submitted")
                return true
            }
        } catch {
            logger.error("Failed to submit crash report: \(error.localizedDescription)")
        }
        return false
    }

    private func formatReportMarkdown(_ report: CrashReport) -> String {
        var md = "# Crash Report\n\n"
        md += "**App Version:** \(report.appVersion)\n"
        md += "**OS Version:** \(report.osVersion)\n"
        md += "**Device:** \(report.deviceModel)\n"
        md += "**Timestamp:** \(ISO8601DateFormatter().string(from: report.timestamp))\n\n"

        if let signal = report.signal {
            md += "**Signal:** \(signal)\n\n"
        }
        if let exception = report.exception {
            md += "**Exception:** \(exception)\n\n"
        }

        md += "## Stack Trace\n```\n\(report.stackTrace)\n```\n"

        if let logs = report.logs, !logs.isEmpty {
            md += "\n## Logs\n```\n\(logs)\n```\n"
        }

        return md
    }

    private func collectLogs() -> String? {
        guard let prefs = preferences, prefs[TelemetryPreferences.crashReportIncludeLogs] else { return nil }
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-300))
            let entries = try store.getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == "org.moonfin.appletv" }
                .suffix(250)
                .map { "[\($0.date)] [\($0.category)] \($0.composedMessage)" }
            return entries.joined(separator: "\n")
        } catch {
            return nil
        }
    }
}
