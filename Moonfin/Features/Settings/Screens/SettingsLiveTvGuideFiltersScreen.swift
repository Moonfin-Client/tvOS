import SwiftUI

struct SettingsLiveTvGuideFiltersScreen: View {
    @EnvironmentObject var container: AppContainer

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Guide Filters") {
            SettingsToggleButton(
                icon: "film",
                heading: "Movies",
                caption: "Show movies in the guide",
                isOn: prefs.binding(for: UserPreferences.liveTvFilterMovies)
            )

            SettingsToggleButton(
                icon: "tv",
                heading: "Series",
                caption: "Show series in the guide",
                isOn: prefs.binding(for: UserPreferences.liveTvFilterSeries)
            )

            SettingsToggleButton(
                icon: "newspaper",
                heading: "News",
                caption: "Show news programs in the guide",
                isOn: prefs.binding(for: UserPreferences.liveTvFilterNews)
            )

            SettingsToggleButton(
                icon: "figure.and.child.holdinghands",
                heading: "Kids",
                caption: "Show kids programs in the guide",
                isOn: prefs.binding(for: UserPreferences.liveTvFilterKids)
            )

            SettingsToggleButton(
                icon: "sportscourt",
                heading: "Sports",
                caption: "Show sports in the guide",
                isOn: prefs.binding(for: UserPreferences.liveTvFilterSports)
            )

            SettingsToggleButton(
                icon: "star.circle",
                heading: "Premieres Only",
                caption: "Show only premiere episodes",
                isOn: prefs.binding(for: UserPreferences.liveTvFilterPremiere)
            )
        }
    }
}
