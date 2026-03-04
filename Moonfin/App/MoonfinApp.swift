import SwiftUI

@main
struct MoonfinApp: App {
    @StateObject private var theme = MoonfinTheme()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(theme)
        }
    }
}
