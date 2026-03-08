import SwiftUI

struct AddToPlaylistDialog: View {
    let itemIds: [String]
    let onDismiss: () -> Void
    let onAdded: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @State private var playlists: [ServerItem] = []
    @State private var isLoading = true
    @State private var showCreateNew = false
    @State private var newPlaylistName = ""
    @State private var errorMessage: String?
    @FocusState private var focusedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(showCreateNew ? "New Playlist" : "Add to Playlist")
                .font(.title2xl)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.top, SpaceTokens.spaceLg)
                .padding(.bottom, SpaceTokens.spaceMd)

            if showCreateNew {
                createNewView
            } else {
                playlistListView
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.bodySm)
                    .foregroundColor(.red)
                    .padding(.horizontal, SpaceTokens.spaceLg)
                    .padding(.vertical, SpaceTokens.spaceXs)
            }

            HStack {
                Spacer()
                FocusableDialogButton(title: "Cancel", action: onDismiss)
                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceMd)
        }
        .frame(width: 600)
        .background(theme.colorScheme.surface)
        .cornerRadius(RadiusTokens.large)
        .onAppear {
            loadPlaylists()
            focusedId = "create"
        }
    }

    @ViewBuilder
    private var playlistListView: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView().tint(theme.colorScheme.onBackground)
                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceLg)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SpaceTokens.spaceXs) {
                    FocusablePlaylistRow(
                        icon: "plus.circle.fill",
                        label: "Create New Playlist",
                        iconColor: theme.accent,
                        action: { showCreateNew = true }
                    )
                    .focused($focusedId, equals: "create")

                    ForEach(playlists) { playlist in
                        FocusablePlaylistRow(
                            icon: "music.note.list",
                            label: playlist.name,
                            action: { addToExistingPlaylist(playlist) }
                        )
                        .focused($focusedId, equals: playlist.id)
                    }
                }
                .padding(.horizontal, SpaceTokens.spaceSm)
            }
            .frame(maxHeight: 400)
        }
    }

    private var createNewView: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            TextField("Playlist Name", text: $newPlaylistName)
                .textFieldStyle(.plain)
                .font(.bodyMd)
                .padding(SpaceTokens.spaceSm)
                .background(Color.white.opacity(0.1))
                .cornerRadius(RadiusTokens.small)
                .padding(.horizontal, SpaceTokens.spaceLg)

            HStack(spacing: SpaceTokens.spaceMd) {
                FocusableDialogButton(title: "Back") {
                    showCreateNew = false
                    newPlaylistName = ""
                }

                FocusableDialogButton(title: "Create") {
                    createNewPlaylist()
                }
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, SpaceTokens.spaceLg)
        }
        .padding(.bottom, SpaceTokens.spaceMd)
    }

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    private func loadPlaylists() {
        Task {
            guard let client, let userId = client.userId else {
                isLoading = false
                return
            }
            do {
                let result = try await client.playlistApi.getPlaylists(userId: userId)
                playlists = result.items
            } catch {
                errorMessage = "Failed to load playlists"
            }
            isLoading = false
        }
    }

    private func addToExistingPlaylist(_ playlist: ServerItem) {
        Task {
            guard let client else { return }
            do {
                try await client.playlistApi.addToPlaylist(
                    playlistId: playlist.id,
                    itemIds: itemIds,
                    userId: client.userId
                )
                onAdded()
            } catch {
                errorMessage = "Failed to add to playlist"
            }
        }
    }

    private func createNewPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        Task {
            guard let client else { return }
            do {
                _ = try await client.playlistApi.createPlaylist(
                    name: name,
                    itemIds: itemIds,
                    mediaType: nil
                )
                onAdded()
            } catch {
                errorMessage = "Failed to create playlist"
            }
        }
    }
}

private struct FocusablePlaylistRow: View {
    let icon: String
    let label: String
    var iconColor: Color?
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(isFocused ? .black : (iconColor ?? theme.colorScheme.onBackground.opacity(0.6)))
                Text(label)
                    .font(.bodyLg)
                    .foregroundColor(isFocused ? .black : theme.colorScheme.onBackground)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? Color.white : Color.clear)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}
