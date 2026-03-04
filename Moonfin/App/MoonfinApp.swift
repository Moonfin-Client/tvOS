import SwiftUI

@main
struct MoonfinApp: App {
    @StateObject private var theme = MoonfinTheme()
    @StateObject private var router = NavigationRouter()
    @StateObject private var settingsRouter = SettingsRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(theme)
                .environmentObject(router)
                .environmentObject(settingsRouter)
        }
    }
}
