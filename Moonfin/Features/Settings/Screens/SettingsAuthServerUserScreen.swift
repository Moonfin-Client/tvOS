import SwiftUI

struct SettingsAuthServerUserScreen: View {
    let serverId: String
    let userId: String
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @State private var showDeleteAlert = false

    private var server: Server? {
        container.serverRepository.storedServers.value.first { $0.id.uuidString == serverId }
    }

    private var user: PrivateUser? {
        guard let server else { return nil }
        return container.serverUserRepository.getStoredServerUsers(server: server)
            .first { $0.id.uuidString == userId }
    }

    var body: some View {
        SettingsScreenLayout(title: "Account") {
            if let server, let user {
                userHeader(user, server: server)

                Divider()
                    .background(theme.colorScheme.listCaption.opacity(0.3))
                    .padding(.vertical, SpaceTokens.spaceXs)

                if user.accessToken != nil {
                    Button(action: {
                        _ = container.authenticationRepository.logout(user: user)
                        settingsRouter.goBack()
                    }) {
                        FocusAwareActionLabel(icon: "rectangle.portrait.and.arrow.right", text: "Sign Out")
                    }
                    .buttonStyle(CleanButtonStyle())
                }

                Button(action: { showDeleteAlert = true }) {
                    FocusAwareActionLabel(icon: "trash", text: "Remove Account", color: .red)
                }
                .buttonStyle(CleanButtonStyle())
                .alert("Remove Account", isPresented: $showDeleteAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Remove", role: .destructive) {
                        container.serverUserRepository.deleteStoredUser(user)
                        settingsRouter.goBack()
                    }
                } message: {
                    Text("This will remove \"\(user.name)\" from this device.")
                }
            }
        }
    }

    private func userHeader(_ user: PrivateUser, server: Server) -> some View {
        VStack(spacing: SpaceTokens.spaceSm) {
            SettingsUserAvatarView(user: user, server: server, size: 64)

            Text(user.name)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)

            Text(server.name)
                .font(.captionXs)
                .foregroundColor(theme.colorScheme.listCaption)

            if user.accessToken != nil {
                HStack(spacing: SpaceTokens.space2xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Signed in")
                        .font(.captionXs)
                }
                .foregroundColor(theme.accent)
            } else {
                Text("Not signed in")
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.listCaption)
            }

            if let lastUsed = user.lastUsed {
                Text("Last used \(lastUsed, style: .relative) ago")
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.listCaption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpaceTokens.spaceSm)
    }

}
