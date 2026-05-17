import SwiftUI

@main
struct MoonfinApp: App {
    @StateObject private var container = AppContainer()
    @StateObject private var theme = MoonfinTheme()
    @StateObject private var router = NavigationRouter()
    @StateObject private var settingsRouter = SettingsRouter()
    @StateObject private var previewManager = PreviewPlayerManager()

    init() {
        ImagePipelineConfig.configure()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(container: container)
                .environmentObject(container)
                .environmentObject(theme)
                .environmentObject(router)
                .environmentObject(settingsRouter)
                .environmentObject(container.featureDegradationManager)
                .environmentObject(container.serverConnectionMonitor)
                .environmentObject(previewManager)
                .rtlAware()
                .environmentObject(LocalizationManager.shared)
                .onAppear {
                    theme.refreshFromPreferences(container.userPreferences)
                }
        }
    }
}

struct AppRootView: View {
    @StateObject private var sessionInitializer: SessionInitializer
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var localization: LocalizationManager

    init(container: AppContainer) {
        _sessionInitializer = StateObject(wrappedValue: SessionInitializer(container: container))
    }

    var body: some View {
        RootView()
            .id(localization.currentLanguageCode)
            .environment(\.locale, localization.locale)
            .environmentObject(sessionInitializer)
            .onOpenURL { url in
                sessionInitializer.handleDeepLink(url: url, router: router)
            }
            .onContinueUserActivity(SpotlightIndexer.activityType) { activity in
                sessionInitializer.handleUserActivity(activity, router: router)
            }
    }
}
