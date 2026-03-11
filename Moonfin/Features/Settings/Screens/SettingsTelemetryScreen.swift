import SwiftUI

struct SettingsTelemetryScreen: View {
    @EnvironmentObject var container: AppContainer

    var body: some View {
        SettingsScreenLayout(title: "Telemetry") {
            SettingsToggleButton(
                icon: "chart.bar",
                heading: "Enable Telemetry",
                caption: "Send anonymous usage data",
                isOn: container.userPreferences.binding(for: UserPreferences.telemetryEnabled)
            )

            SettingsToggleButton(
                icon: "ladybug",
                heading: "Send Crash Reports",
                caption: "Automatically send crash reports to your server",
                isOn: container.telemetryPreferences.binding(for: TelemetryPreferences.crashReportEnabled)
            )

            SettingsToggleButton(
                icon: "doc.text",
                heading: "Include Logs",
                caption: "Attach recent app logs to crash reports",
                isOn: container.telemetryPreferences.binding(for: TelemetryPreferences.crashReportIncludeLogs)
            )
        }
    }
}
