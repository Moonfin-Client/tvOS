import SwiftUI

struct SettingsMainScreen: View {
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?
    @Namespace private var screenNamespace

    var body: some View {
        SettingsScreenLayout(title: Strings.settings) {
            SettingsListButton(
                icon: "lock",
                heading: "Account and Security",
                caption: "Authentication, PIN, ratings, and safety settings",
                action: { settingsRouter.navigate(to: .accountAndSecurity) }
            )
            .focused($focusedRoute, equals: .accountAndSecurity)
            .prefersDefaultFocus(in: screenNamespace)

            SettingsListButton(
                icon: "paintpalette",
                heading: "Personalization",
                caption: "General style, navigation, home, and library settings",
                action: { settingsRouter.navigate(to: .personalization) }
            )
            .focused($focusedRoute, equals: .personalization)

            SettingsListButton(
                icon: "rectangle.inset.filled",
                heading: "Dynamic Content",
                caption: "Media bar, previews, and seasonal effects",
                action: { settingsRouter.navigate(to: .dynamicContent) }
            )
            .focused($focusedRoute, equals: .dynamicContent)

            SettingsListButton(
                icon: "play.circle",
                heading: "Playback and SyncPlay",
                caption: "Video, audio, subtitles, automation, sync, and advanced playback",
                action: { settingsRouter.navigate(to: .playbackAndSyncPlay) }
            )
            .focused($focusedRoute, equals: .playbackAndSyncPlay)

            SettingsListButton(
                icon: "puzzlepiece.extension",
                heading: "Integrations",
                caption: "Plugin sync, ratings, Seerr, and integration status",
                action: { settingsRouter.navigate(to: .integrations) }
            )
            .focused($focusedRoute, equals: .integrations)

            SettingsListButton(
                icon: "info.circle",
                heading: "About",
                caption: "Version info, legal notices, support, and diagnostics",
                action: { settingsRouter.navigate(to: .about) }
            )
            .focused($focusedRoute, equals: .about)
        }
        .focusScope(screenNamespace)
        .defaultFocus($focusedRoute, .accountAndSecurity)
        .restoresFocus($focusedRoute)
        .onAppear {
            guard settingsRouter.path.count == 1,
                  settingsRouter.path.first == .main,
                  settingsRouter.lastPoppedRoute == nil else { return }
            focusedRoute = .accountAndSecurity
        }
    }
}
