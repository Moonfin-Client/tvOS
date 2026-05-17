import SwiftUI

struct SettingsDynamicContentScreen: View {
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    var body: some View {
        SettingsScreenLayout(title: "Dynamic Content") {
            SettingsListButton(
                icon: "rectangle.inset.filled",
                heading: "Media Bar",
                caption: "Slides, filters, and featured content settings",
                action: { settingsRouter.navigate(to: .dynamicContentMediaBar) }
            )
            .focused($focusedRoute, equals: .dynamicContentMediaBar)

            SettingsListButton(
                icon: "play.rectangle",
                heading: "Local Previews",
                caption: "Trailer previews, media previews, and preview audio",
                action: { settingsRouter.navigate(to: .dynamicContentLocalPreviews) }
            )
            .focused($focusedRoute, equals: .dynamicContentLocalPreviews)

            SettingsListButton(
                icon: "sparkles",
                heading: "Seasonal Effects",
                caption: "Decorative seasonal overlays",
                action: { settingsRouter.navigate(to: .dynamicContentSeasonalEffects) }
            )
            .focused($focusedRoute, equals: .dynamicContentSeasonalEffects)
        }
        .restoresFocus($focusedRoute)
    }
}
