import SwiftUI

struct SettingsAuthServerScreen: View {
    let serverId: String
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @State private var showDeleteAlert = false

    private var server: Server? {
        container.serverRepository.storedServers.value.first { $0.id.uuidString == serverId }
    }

    private var users: [PrivateUser] {
        guard let server else { return [] }
        return container.serverUserRepository.getStoredServerUsers(server: server)
    }

    var body: some View {
        SettingsScreenLayout(title: "Server") {
            if let server {
                serverHeader(server)

                Divider()
                    .background(theme.colorScheme.listCaption.opacity(0.3))
                    .padding(.vertical, SpaceTokens.spaceXs)

                if !users.isEmpty {
                    Text("Accounts")
                        .font(.bodyLg)
                        .fontWeight(.semibold)
                        .foregroundColor(theme.colorScheme.onBackground)
                        .padding(.bottom, SpaceTokens.space2xs)

                    ForEach(users, id: \.id) { user in
                        userRow(user, server: server)
                    }
                }

                Divider()
                    .background(theme.colorScheme.listCaption.opacity(0.3))
                    .padding(.vertical, SpaceTokens.spaceXs)

                Button(action: { showDeleteAlert = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Remove Server")
                    }
                    .font(.bodyMd)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceSm)
                }
                .buttonStyle(CleanButtonStyle())
                .alert("Remove Server", isPresented: $showDeleteAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Remove", role: .destructive) {
                        _ = container.serverRepository.deleteServer(id: server.id)
                        settingsRouter.goBack()
                    }
                } message: {
                    Text("This will remove \"\(server.name)\" and all stored accounts.")
                }
            }
        }
    }

    private func serverHeader(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.space2xs) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: server.serverType == .jellyfin ? "server.rack" : "tv")
                    .font(.system(size: 24))
                    .foregroundColor(theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.bodyLg)
                        .fontWeight(.semibold)
                        .foregroundColor(theme.colorScheme.onBackground)

                    Text(server.address)
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.listCaption)
                }
            }

            if let version = server.version {
                Text("\(server.serverType == .jellyfin ? "Jellyfin" : "Emby") \(version)")
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.listCaption)
            }
        }
        .padding(.bottom, SpaceTokens.spaceSm)
    }

    private func userRow(_ user: PrivateUser, server: Server) -> some View {
        Button {
            settingsRouter.navigate(to: .authenticationServerUser(serverId: serverId, userId: user.id.uuidString))
        } label: {
            HStack(spacing: SpaceTokens.spaceSm) {
                SettingsUserAvatarView(user: user, server: server, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.listHeadline)

                    if let lastUsed = user.lastUsed {
                        Text("Last used \(lastUsed, style: .relative) ago")
                            .font(.captionXs)
                            .foregroundColor(theme.colorScheme.listCaption)
                    }
                }

                Spacer()

                if user.accessToken != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(theme.accent)
                        .font(.system(size: 14))
                }

                Image(systemName: "chevron.right")
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.listCaption)
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                    .fill(theme.colorScheme.listButton)
            )
        }
        .buttonStyle(CleanButtonStyle())
    }

}

struct SettingsUserAvatarView: View {
    let user: PrivateUser
    let server: Server
    let size: CGFloat

    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        let imageUrl = container.authenticationRepository.getUserImageUrl(server: server, user: user)
            .flatMap { URL(string: $0) }

        if let imageUrl {
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                default:
                    defaultAvatar
                }
            }
        } else {
            defaultAvatar
        }
    }

    private var defaultAvatar: some View {
        Image(systemName: "person.circle.fill")
            .font(.system(size: size))
            .foregroundColor(theme.colorScheme.listCaption)
    }
}
