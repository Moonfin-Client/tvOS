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

    private func showCreateView() {
        showCreateNew = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedId = "textfield"
        }
    }

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
                DetailsGlassDialogButton(title: "Cancel", action: onDismiss)
                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceMd)
        }
        .frame(width: 600)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(Color(white: 0.12).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.large)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
        .cornerRadius(RadiusTokens.large)
        .focusSection()
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
                        action: { showCreateView() }
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
                .focused($focusedId, equals: "textfield")
                .textFieldStyle(.plain)
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.vertical, SpaceTokens.spaceSm + 4)
                .background(
                    RoundedRectangle(cornerRadius: RadiusTokens.large)
                        .fill(theme.colorScheme.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.large)
                        .stroke(
                            focusedId == "textfield" ? Color.white.opacity(0.9) : Color.white.opacity(0.22),
                            lineWidth: focusedId == "textfield" ? 2 : 1
                        )
                )
                .padding(.horizontal, SpaceTokens.spaceLg)

            HStack(spacing: SpaceTokens.spaceMd) {
                DetailsGlassDialogButton(title: "Back") {
                    showCreateNew = false
                    newPlaylistName = ""
                    focusedId = "create"
                }

                DetailsGlassDialogButton(title: "Create") {
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
                    .foregroundColor(iconColor ?? theme.colorScheme.onBackground.opacity(0.6))
                Text(label)
                    .font(.bodyLg)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? Color.white.opacity(0.24) : Color.white.opacity(0.08))
                    .background(
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .stroke(isFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.22), lineWidth: isFocused ? 2 : 1)
                    )
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}

struct DetailsGlassDialogButton: View {
    let title: String
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bodyMd)
                .fontWeight(.medium)
                .foregroundColor(isFocused ? .white : theme.colorScheme.onBackground)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.vertical, SpaceTokens.spaceSm)
                .background(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .fill(isFocused ? Color.white.opacity(0.26) : Color.white.opacity(0.08))
                        .background(
                            RoundedRectangle(cornerRadius: RadiusTokens.small)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: RadiusTokens.small)
                                .stroke(isFocused ? Color.white.opacity(0.92) : Color.white.opacity(0.24), lineWidth: isFocused ? 2 : 1)
                        )
                )
                .opacity(isEnabled ? 1.0 : 0.45)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}
