import SwiftUI

struct SettingsLiveTvGuideOptionsScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: Strings.liveTvGuide) {
            SettingsListButton(
                icon: "arrow.up.arrow.down",
                heading: Strings.channelOrder,
                caption: prefs[UserPreferences.liveTvChannelOrder].displayName,
                action: { settingsRouter.navigate(to: .liveTvGuideChannelOrder) }
            )
            .focused($focusedRoute, equals: .liveTvGuideChannelOrder)

            SettingsToggleButton(
                icon: "star",
                heading: Strings.liveTvFavoritesAtTop,
                caption: Strings.liveTvShowFavoriteChannelsFirst,
                isOn: prefs.binding(for: UserPreferences.liveTvFavsAtTop)
            )

            SettingsToggleButton(
                icon: "paintpalette",
                heading: Strings.liveTvColorCodedBackgrounds,
                caption: Strings.liveTvColorGuideEntriesByGenre,
                isOn: prefs.binding(for: UserPreferences.liveTvColorCodeGuide)
            )

            Text(Strings.liveTvGuideIndicatorsUpper)
                .font(.captionSm)
                .foregroundColor(theme.colorScheme.listCaption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, SpaceTokens.spaceMd)

            SettingsToggleButton(
                icon: "sparkle",
                heading: Strings.liveTvShowHdIndicator,
                caption: Strings.liveTvDisplayHdBadge,
                isOn: prefs.binding(for: UserPreferences.liveTvShowHDIndicator)
            )

            SettingsToggleButton(
                icon: "dot.radiowaves.left.and.right",
                heading: Strings.liveTvShowLiveIndicator,
                caption: Strings.liveTvDisplayLiveBadge,
                isOn: prefs.binding(for: UserPreferences.liveTvShowLiveIndicator)
            )

            SettingsToggleButton(
                icon: "bell.badge",
                heading: Strings.liveTvShowNewIndicator,
                caption: Strings.liveTvDisplayNewBadge,
                isOn: prefs.binding(for: UserPreferences.liveTvShowNewIndicator)
            )

            SettingsToggleButton(
                icon: "arrow.2.squarepath",
                heading: Strings.liveTvShowRepeatIndicator,
                caption: Strings.liveTvDisplayRepeatBadge,
                isOn: prefs.binding(for: UserPreferences.liveTvShowRepeatIndicator)
            )

            SettingsListButton(
                icon: "line.3.horizontal.decrease.circle",
                heading: Strings.liveTvGuideFilters,
                caption: Strings.liveTvFilterGuideByContentType,
                action: { settingsRouter.navigate(to: .liveTvGuideFilters) }
            )
            .focused($focusedRoute, equals: .liveTvGuideFilters)
        }
        .restoresFocus($focusedRoute)
    }
}
