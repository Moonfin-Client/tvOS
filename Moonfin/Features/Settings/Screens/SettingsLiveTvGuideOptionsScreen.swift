import SwiftUI

struct SettingsLiveTvGuideOptionsScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Live TV Guide") {
            SettingsListButton(
                icon: "arrow.up.arrow.down",
                heading: "Channel Order",
                caption: prefs[UserPreferences.liveTvChannelOrder].displayName,
                action: { settingsRouter.navigate(to: .liveTvGuideChannelOrder) }
            )
            .focused($focusedRoute, equals: .liveTvGuideChannelOrder)

            SettingsToggleButton(
                icon: "star",
                heading: "Favorites at Top",
                caption: "Show favorite channels first",
                isOn: prefs.binding(for: UserPreferences.liveTvFavsAtTop)
            )

            SettingsToggleButton(
                icon: "paintpalette",
                heading: "Color-Coded Backgrounds",
                caption: "Color guide entries by genre",
                isOn: prefs.binding(for: UserPreferences.liveTvColorCodeGuide)
            )

            Text("INDICATORS")
                .font(.captionSm)
                .foregroundColor(theme.colorScheme.listCaption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, SpaceTokens.spaceMd)

            SettingsToggleButton(
                icon: "sparkle",
                heading: "Show HD Indicator",
                caption: "Display HD badge on channels",
                isOn: prefs.binding(for: UserPreferences.liveTvShowHDIndicator)
            )

            SettingsToggleButton(
                icon: "dot.radiowaves.left.and.right",
                heading: "Show Live Indicator",
                caption: "Display live badge on programs",
                isOn: prefs.binding(for: UserPreferences.liveTvShowLiveIndicator)
            )

            SettingsToggleButton(
                icon: "bell.badge",
                heading: "Show New Indicator",
                caption: "Display badge on new programs",
                isOn: prefs.binding(for: UserPreferences.liveTvShowNewIndicator)
            )

            SettingsToggleButton(
                icon: "arrow.2.squarepath",
                heading: "Show Repeat Indicator",
                caption: "Display badge on repeat programs",
                isOn: prefs.binding(for: UserPreferences.liveTvShowRepeatIndicator)
            )

            SettingsListButton(
                icon: "line.3.horizontal.decrease.circle",
                heading: "Guide Filters",
                caption: "Filter guide by content type",
                action: { settingsRouter.navigate(to: .liveTvGuideFilters) }
            )
            .focused($focusedRoute, equals: .liveTvGuideFilters)
        }
        .restoresFocus($focusedRoute)
    }
}
