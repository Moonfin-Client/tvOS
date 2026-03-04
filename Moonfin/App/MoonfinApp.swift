import SwiftUI

@main
struct MoonfinApp: App {
    @StateObject private var container = AppContainer()
    @StateObject private var theme = MoonfinTheme()
    @StateObject private var router = NavigationRouter()
    @StateObject private var settingsRouter = SettingsRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(theme)
                .environmentObject(router)
                .environmentObject(settingsRouter)
        }
    }
}
