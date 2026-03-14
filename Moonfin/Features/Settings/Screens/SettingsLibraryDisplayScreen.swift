import SwiftUI

struct SettingsLibraryDisplayScreen: View {
    let itemId: String
    let displayPreferencesId: String
    let serverId: String
    let userId: String

    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: LibraryPreferences {
        LibraryPreferences(store: container.preferenceStore, libraryId: itemId)
    }

    var body: some View {
        SettingsScreenLayout(title: "Display Settings") {
            SettingsListButton(
                icon: "rectangle.expand.vertical",
                heading: "Image Size",
                caption: "Size of cards in the grid",
                trailingText: prefs.posterSize.displayName,
                action: {
                    settingsRouter.navigate(to: .librariesDisplayImageSize(
                        itemId: itemId,
                        displayPreferencesId: displayPreferencesId,
                        serverId: serverId,
                        userId: userId
                    ))
                }
            )

            SettingsListButton(
                icon: "photo",
                heading: "Image Type",
                caption: "Type of image shown on cards",
                trailingText: prefs.imageType.displayName,
                action: {
                    settingsRouter.navigate(to: .librariesDisplayImageType(
                        itemId: itemId,
                        displayPreferencesId: displayPreferencesId,
                        serverId: serverId,
                        userId: userId
                    ))
                }
            )

            SettingsListButton(
                icon: "arrow.up.arrow.down",
                heading: "Grid Direction",
                caption: "Scroll orientation for the grid",
                trailingText: prefs.gridDirection.displayName,
                action: {
                    settingsRouter.navigate(to: .librariesDisplayGrid(
                        itemId: itemId,
                        displayPreferencesId: displayPreferencesId,
                        serverId: serverId,
                        userId: userId
                    ))
                }
            )
        }
    }
}
