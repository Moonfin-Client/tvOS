import SwiftUI

struct SettingsAuthenticationAutoSignInScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme

    private var servers: [Server] {
        container.serverRepository.storedServers.value
    }

    var body: some View {
        SettingsScreenLayout(title: "Auto Sign In") {
            optionRow(
                icon: "nosign",
                heading: "Disabled",
                caption: "Require sign in every launch",
                isSelected: container.authPreferences.autoLoginBehavior == .disabled,
                action: {
                    container.authPreferences.autoLoginBehavior = .disabled
                    settingsRouter.goBack()
                }
            )

            optionRow(
                icon: "clock.arrow.circlepath",
                heading: "Last User",
                caption: "Automatically sign in with the last signed-in account",
                isSelected: container.authPreferences.autoLoginBehavior == .lastUser,
                action: {
                    container.authPreferences.autoLoginBehavior = .lastUser
                    settingsRouter.goBack()
                }
            )

            ForEach(servers) { server in
                let users = container.serverUserRepository.getStoredServerUsers(server: server)
                if !users.isEmpty {
                    Divider()
                        .background(theme.colorScheme.listCaption.opacity(0.3))
                        .padding(.vertical, SpaceTokens.spaceXs)

                    Text(server.name)
                        .font(.bodyLg)
                        .fontWeight(.semibold)
                        .foregroundColor(theme.colorScheme.onBackground)
                        .padding(.bottom, SpaceTokens.space2xs)

                    ForEach(users, id: \.id) { user in
                        userOptionRow(server: server, user: user)
                    }
                }
            }
        }
        .onAppear {
            container.serverRepository.loadStoredServers()
        }
    }

    @ViewBuilder
    private func optionRow(
        icon: String,
        heading: String,
        caption: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SettingsItemContent(icon: icon, heading: heading, caption: caption) { isFocused in
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.bodyMd)
                    .foregroundColor(isSelected
                        ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                        : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
            }
        }
        .buttonStyle(CleanButtonStyle())
    }

    @ViewBuilder
    private func userOptionRow(server: Server, user: PrivateUser) -> some View {
        let serverId = server.id.uuidString
        let userId = user.id.uuidString
        let isSelected = container.authPreferences.autoLoginBehavior == .specificUser
            && container.authPreferences.autoLoginServerId == serverId
            && container.authPreferences.autoLoginUserId == userId

        Button {
            container.authPreferences.autoLoginBehavior = .specificUser
            container.authPreferences.autoLoginServerId = serverId
            container.authPreferences.autoLoginUserId = userId
            settingsRouter.goBack()
        } label: {
            HStack(spacing: SpaceTokens.spaceSm) {
                SettingsUserAvatarView(user: user, server: server, size: 28)

                Text(user.name)
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.listHeadline)

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.bodyMd)
                    .foregroundColor(isSelected ? theme.accent : theme.colorScheme.listCaption)
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
