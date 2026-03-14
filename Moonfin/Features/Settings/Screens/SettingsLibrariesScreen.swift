import SwiftUI

struct SettingsLibrariesScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme

    @State private var libraries: [AggregatedLibrary] = []
    @State private var isLoading = true

    var body: some View {
        SettingsScreenLayout(title: "Libraries") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceLg)
            } else if libraries.isEmpty {
                Text("No libraries found")
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceLg)
            } else {
                ForEach(libraries, id: \.library.id) { entry in
                    SettingsListButton(
                        icon: libraryIcon(for: entry.library.collectionType),
                        heading: entry.displayName,
                        caption: libraryCaption(for: entry),
                        action: {
                            settingsRouter.navigate(to: .librariesDisplay(
                                itemId: entry.library.id,
                                displayPreferencesId: entry.library.id,
                                serverId: entry.server.id.uuidString,
                                userId: entry.userId.uuidString
                            ))
                        }
                    )
                }
            }
        }
        .task { await loadLibraries() }
    }

    private func loadLibraries() async {
        let results = await container.multiServerRepository.getAggregatedLibraries()
        libraries = results
        isLoading = false
    }

    private func libraryCaption(for entry: AggregatedLibrary) -> String {
        let prefs = LibraryPreferences(store: container.preferenceStore, libraryId: entry.library.id)
        return "\(prefs.posterSize.displayName) · \(prefs.imageType.displayName)"
    }

    private func libraryIcon(for collectionType: String?) -> String {
        guard let ct = collectionType?.lowercased() else { return "folder" }
        switch ct {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "music": return "music.note"
        case "books": return "book"
        case "photos": return "photo"
        case "homevideos": return "video"
        case "boxsets": return "square.stack"
        case "playlists": return "list.bullet"
        case "livetv": return "antenna.radiowaves.left.and.right"
        default: return "folder"
        }
    }
}
