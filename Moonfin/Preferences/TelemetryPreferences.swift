import Foundation
import SwiftUI

final class TelemetryPreferences {
    private var store: PreferenceStore

    static let crashReportEnabled = Preference(key: "crash_report_enabled", defaultValue: true)
    static let crashReportIncludeLogs = Preference(key: "crash_report_include_logs", defaultValue: true)
    static let crashReportUrl = Preference(key: "crash_report_url", defaultValue: "")
    static let crashReportToken = Preference(key: "crash_report_token", defaultValue: "")

    init(store: PreferenceStore) {
        self.store = store
    }

    subscript<T>(preference: Preference<T>) -> T {
        get { store[preference] }
        set { store[preference] = newValue }
    }

    func binding<T>(for preference: Preference<T>) -> Binding<T> {
        Binding(
            get: { self[preference] },
            set: { self[preference] = $0 }
        )
    }
}
