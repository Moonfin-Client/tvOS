import SwiftUI

struct SettingsTelemetryScreen: View {
    @EnvironmentObject var container: AppContainer

    var body: some View {
        SettingsScreenLayout(title: "Telemetry") {
            SettingsToggleButton(
                icon: "chart.bar",
                heading: "Enable Telemetry",
                caption: "Send anonymous usage data and crash reports",
                isOn: container.userPreferences.binding(for: UserPreferences.telemetryEnabled)
            )
        }
    }
}
