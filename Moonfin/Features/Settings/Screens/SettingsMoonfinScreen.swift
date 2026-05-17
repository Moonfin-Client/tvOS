import SwiftUI

struct SettingsMoonfinScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @State private var refreshTrigger = 0
    @State private var statusText: String?

    private var prefs: UserPreferences { container.userPreferences }
    private var profileControlsVisible: Bool {
        prefs[UserPreferences.pluginSyncEnabled] && container.pluginSyncService.isPluginAvailable
    }

    var body: some View {
        SettingsScreenLayout(title: "Plugin") {
            let _ = refreshTrigger

            SettingsToggleButton(
                icon: "arrow.triangle.2.circlepath",
                heading: "Server Plugin Sync",
                caption: "Enable push and pull settings sync with the server plugin",
                isOn: pluginSyncBinding
            )

            if profileControlsVisible {
                SettingsListButton(
                    icon: "person.crop.rectangle.stack",
                    heading: "Customization Profile",
                    caption: "Select profile target for sync actions",
                    trailingText: prefs[UserPreferences.pluginCustomizationProfile].displayName,
                    action: { settingsRouter.navigate(to: .pluginCustomizationProfile) }
                )

                SettingsListButton(
                    icon: "icloud.and.arrow.down",
                    heading: "Load Profile",
                    caption: "Pull remote profile settings into this device",
                    action: {
                        Task {
                            await container.pluginSyncService.initialSync()
                            statusText = "Profile loaded"
                            refreshTrigger += 1
                        }
                    }
                )

                SettingsListButton(
                    icon: "icloud.and.arrow.up",
                    heading: "Save Profile",
                    caption: "Push local settings to the selected profile",
                    action: {
                        Task {
                            await container.pluginSyncService.syncOnStartup()
                            statusText = "Profile saved"
                            refreshTrigger += 1
                        }
                    }
                )
            }

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)) { _ in
            refreshTrigger += 1
        }
        .onReceive(container.pluginSyncService.$syncCompletedCount) { _ in
            refreshTrigger += 1
        }
    }

    private var pluginSyncBinding: Binding<Bool> {
        Binding(
            get: { prefs[UserPreferences.pluginSyncEnabled] },
            set: { newValue in
                prefs[UserPreferences.pluginSyncEnabled] = newValue
                prefs[UserPreferences.pluginSyncAutoDetected] = true
                refreshTrigger += 1
                if newValue {
                    Task { await container.pluginSyncService.initialSync() }
                } else {
                    container.pluginSyncService.unregisterChangeListener()
                }
            }
        )
    }
}
