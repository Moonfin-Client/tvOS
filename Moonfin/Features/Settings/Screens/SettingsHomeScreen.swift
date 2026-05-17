import SwiftUI

struct SettingsHomeScreen: View {
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var container: AppContainer
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Home Screen") {
            SettingsListButton(
                icon: "list.bullet",
                heading: "Home Sections",
                caption: "Open row enablement and ordering",
                action: { settingsRouter.navigate(to: .homeSections) }
            )
            .focused($focusedRoute, equals: .homeSections)

            SettingsListButton(
                icon: "photo.on.rectangle",
                heading: "Per-Row Image Type Selection",
                caption: "Choose image style per enabled row",
                action: { settingsRouter.navigate(to: .homeRowsImageType) }
            )
            .focused($focusedRoute, equals: .homeRowsImageType)

            SettingsToggleButton(
                icon: "arrow.left.arrow.right",
                heading: "Merge Continue Watching And Next Up",
                caption: "Combine Continue Watching and Next Up rows",
                isOn: prefs.binding(for: UserPreferences.mergeContinueWatchingNextUp)
            )

            SettingsToggleButton(
                icon: "heart",
                heading: "Display Favorites Rows",
                caption: "Control whether favorites rows are shown",
                isOn: prefs.binding(for: UserPreferences.displayFavoritesRows)
            )

            if prefs[UserPreferences.displayFavoritesRows] {
                SettingsListButton(
                    icon: "arrow.up.arrow.down",
                    heading: "Favorites Row Sorting",
                    caption: "Choose sorting for favorites rows",
                    trailingText: prefs[UserPreferences.favoritesRowSortBy].displayName,
                    action: { settingsRouter.navigate(to: .homeFavoritesSortBy) }
                )
                .focused($focusedRoute, equals: .homeFavoritesSortBy)
            }

            SettingsToggleButton(
                icon: "square.stack.3d.down.right",
                heading: "Display Collections Rows",
                caption: "Control whether collections rows are shown",
                isOn: prefs.binding(for: UserPreferences.displayCollectionsRows)
            )

            if prefs[UserPreferences.displayCollectionsRows] {
                SettingsListButton(
                    icon: "arrow.up.arrow.down",
                    heading: "Collections Row Sorting",
                    caption: "Choose sorting for collections rows",
                    trailingText: prefs[UserPreferences.collectionsRowSortBy].displayName,
                    action: { settingsRouter.navigate(to: .homeCollectionsSortBy) }
                )
                .focused($focusedRoute, equals: .homeCollectionsSortBy)
            }

            SettingsToggleButton(
                icon: "theatermasks",
                heading: "Display Genres Rows",
                caption: "Control whether genres rows are shown",
                isOn: prefs.binding(for: UserPreferences.displayGenresRows)
            )

            if prefs[UserPreferences.displayGenresRows] {
                SettingsListButton(
                    icon: "arrow.up.arrow.down",
                    heading: "Genres Row Sorting",
                    caption: "Choose sorting for genres rows",
                    trailingText: prefs[UserPreferences.genresRowSortBy].displayName,
                    action: { settingsRouter.navigate(to: .homeGenresSortBy) }
                )
                .focused($focusedRoute, equals: .homeGenresSortBy)

                SettingsListButton(
                    icon: "line.3.horizontal.decrease.circle",
                    heading: "Genres Row Items",
                    caption: "Restrict genre rows to media types",
                    trailingText: prefs[UserPreferences.genresRowItems].displayName,
                    action: { settingsRouter.navigate(to: .homeGenresItems) }
                )
                .focused($focusedRoute, equals: .homeGenresItems)
            }

            SettingsToggleButton(
                icon: "photo.on.rectangle.angled",
                heading: "Series Thumbnails",
                caption: "Use series image thumbnails on home rows",
                isOn: prefs.binding(for: UserPreferences.homeImageUseSeriesImage)
            )

            SettingsListButton(
                icon: "rectangle.expand.vertical",
                heading: "Poster Size",
                caption: "Set global poster size on home rows",
                trailingText: prefs[UserPreferences.homePosterSize].displayName,
                action: { settingsRouter.navigate(to: .homePosterSize) }
            )
            .focused($focusedRoute, equals: .homePosterSize)

            SettingsToggleButton(
                icon: "info.circle",
                heading: "Home Row Info Overlay",
                caption: "Show title and metadata overlays on row cards",
                isOn: prefs.binding(for: UserPreferences.homeRowInfoOverlay)
            )

            SettingsToggleButton(
                icon: "music.note.house",
                heading: "Theme Music On Home Rows",
                caption: "Play theme music while browsing home rows",
                isOn: prefs.binding(for: UserPreferences.themeMusicOnHomeRows)
            )
        }
        .restoresFocus($focusedRoute)
    }
}
