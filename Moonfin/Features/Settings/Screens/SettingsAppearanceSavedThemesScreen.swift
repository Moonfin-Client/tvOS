import SwiftUI

struct SettingsAppearanceSavedThemesScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: MoonfinTheme

    @State private var savedThemes: [SavedThemeEntry] = []
    @State private var isLoading = false
    @State private var deletingThemeId: String?
    @State private var statusMessage: String?
    @State private var pendingDelete: SavedThemeEntry?

    var body: some View {
        SettingsScreenLayout(title: "Saved Themes") {
            Text("These themes were downloaded from the Moonfin plugin for the current server. Deleting removes only this local copy.")
                .font(.captionXs)
                .foregroundColor(theme.colorScheme.listCaption)
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.bottom, SpaceTokens.spaceSm)

            if let statusMessage {
                Text(statusMessage)
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceMd)
                    .padding(.bottom, SpaceTokens.spaceXs)
            }

            if isLoading {
                HStack(spacing: SpaceTokens.spaceSm) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading saved themes...")
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.listCaption)
                }
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.vertical, SpaceTokens.spaceSm)
            }

            if !isLoading && savedThemes.isEmpty {
                Text("No saved themes were found for this server.")
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceMd)
                    .padding(.vertical, SpaceTokens.spaceSm)
            }

            ForEach(savedThemes) { entry in
                Button {
                    pendingDelete = entry
                } label: {
                    SettingsItemContent(
                        icon: "square.and.arrow.down",
                        heading: entry.displayName,
                        caption: entry.id
                    ) { isFocused in
                        if deletingThemeId == entry.id {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.bodyMd)
                                .foregroundColor(
                                    isFocused ? theme.colorScheme.listHeadlineFocused : Color.red
                                )
                        }
                    }
                }
                .buttonStyle(CleanButtonStyle())
                .disabled(deletingThemeId != nil)
            }
        }
        .task {
            reloadSavedThemes()
        }
        .alert(item: $pendingDelete) { entry in
            Alert(
                title: Text("Delete Saved Theme"),
                message: Text("Delete \"\(entry.displayName)\" from this device cache?"),
                primaryButton: .destructive(Text("Delete")) {
                    deleteTheme(entry)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func reloadSavedThemes() {
        isLoading = true
        savedThemes = container.pluginSyncService.listSavedThemes()
        isLoading = false
    }

    private func deleteTheme(_ entry: SavedThemeEntry) {
        deletingThemeId = entry.id

        let deleted = container.pluginSyncService.deleteSavedTheme(themeId: entry.id)
        statusMessage = deleted
            ? "Deleted \"\(entry.displayName)\" from this device."
            : "Could not delete \"\(entry.displayName)\"."

        reloadSavedThemes()
        deletingThemeId = nil
    }
}
