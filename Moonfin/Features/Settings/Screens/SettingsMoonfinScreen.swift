import SwiftUI

struct SettingsMoonfinScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @State private var refreshTrigger = 0
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }
    private var pluginEnabled: Bool { prefs[UserPreferences.pluginSyncEnabled] }

    var body: some View {
        SettingsScreenLayout(title: Strings.plugin) {
            let _ = refreshTrigger

            SettingsToggleButton(
                icon: "arrow.triangle.2.circlepath",
                heading: Strings.pluginSync,
                caption: Strings.pluginSyncDescription,
                isOn: pluginSyncBinding
            )

            SettingsListButton(
                icon: "rectangle.topthird.inset.filled",
                heading: Strings.toolbar,
                caption: Strings.pluginToolbarSummary,
                action: { settingsRouter.navigate(to: .pluginToolbar) }
            )
            .focused($focusedRoute, equals: .pluginToolbar)

            SettingsListButton(
                icon: "rectangle.inset.filled",
                heading: Strings.mediaBarTitle,
                caption: Strings.pluginMediaBarSummary,
                action: { settingsRouter.navigate(to: .pluginMediaBar) }
            )
            .focused($focusedRoute, equals: .pluginMediaBar)

            SettingsListButton(
                icon: "photo.artframe",
                heading: Strings.backgrounds,
                caption: Strings.pluginBackgroundsSummary,
                action: { settingsRouter.navigate(to: .pluginBackgrounds) }
            )
            .focused($focusedRoute, equals: .pluginBackgrounds)

            SettingsListButton(
                icon: "play.rectangle",
                heading: Strings.previewsAndMusic,
                caption: Strings.pluginPreviewsMusicSummary,
                action: { settingsRouter.navigate(to: .pluginPreviewsMusic) }
            )
            .focused($focusedRoute, equals: .pluginPreviewsMusic)

            SettingsListButton(
                icon: "puzzlepiece.extension",
                heading: Strings.integrations,
                caption: Strings.pluginIntegrationsSummary,
                action: { settingsRouter.navigate(to: .pluginIntegrations) }
            )
            .focused($focusedRoute, equals: .pluginIntegrations)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)) { _ in
            refreshTrigger += 1
        }
        .onReceive(container.pluginSyncService.$syncCompletedCount) { _ in
            refreshTrigger += 1
        }
        .restoresFocus($focusedRoute)
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
