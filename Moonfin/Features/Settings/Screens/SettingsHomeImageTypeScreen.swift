import SwiftUI

struct SettingsHomeImageTypeScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Image Type") {
            SettingsListButton(
                icon: "play.rectangle",
                heading: "Continue Watching",
                caption: "Image type for continue watching rows",
                trailingText: prefs[UserPreferences.homeImageTypeContinueWatching].displayName,
                action: { settingsRouter.navigate(to: .homeImageTypeContinueWatching) }
            )
            .focused($focusedRoute, equals: .homeImageTypeContinueWatching)

            SettingsListButton(
                icon: "sparkles.rectangle.stack",
                heading: "Next Up",
                caption: "Image type for next up rows",
                trailingText: prefs[UserPreferences.homeImageTypeNextUp].displayName,
                action: { settingsRouter.navigate(to: .homeImageTypeNextUp) }
            )
            .focused($focusedRoute, equals: .homeImageTypeNextUp)

            SettingsListButton(
                icon: "rectangle.stack",
                heading: "Libraries",
                caption: "Image type for library rows",
                trailingText: prefs[UserPreferences.homeImageTypeLibraries].displayName,
                action: { settingsRouter.navigate(to: .homeImageTypeLibraries) }
            )
            .focused($focusedRoute, equals: .homeImageTypeLibraries)

            SettingsListButton(
                icon: "tv",
                heading: "Live TV",
                caption: "Image type for live TV rows",
                trailingText: prefs[UserPreferences.homeImageTypeLiveTv].displayName,
                action: { settingsRouter.navigate(to: .homeImageTypeLiveTv) }
            )
            .focused($focusedRoute, equals: .homeImageTypeLiveTv)

            Divider()
                .background(theme.colorScheme.listCaption.opacity(0.3))
                .padding(.vertical, SpaceTokens.spaceXs)

            SettingsToggleButton(
                icon: "tv.and.mediabox",
                heading: "Use Series Image",
                caption: "Show series poster instead of episode image",
                isOn: prefs.binding(for: UserPreferences.homeImageUseSeriesImage)
            )
        }
        .restoresFocus($focusedRoute)
    }
}
