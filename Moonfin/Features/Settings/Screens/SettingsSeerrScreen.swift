import SwiftUI

struct SettingsSeerrScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedRoute: SettingsRoute?

    @State private var fetchLimit: SeerrFetchLimit = .medium
    @State private var seerrEnabled = false
    @State private var isAuthenticated = false
    @State private var authType: SeerrAuthType = .jellyfin
    @State private var usernameOrEmail = ""
    @State private var password = ""
    @State private var authMessage: String?
    @State private var blockNsfw = true
    @State private var showInNavigation = true
    @State private var showInToolbar = true
    @State private var showRequestStatus = true

    private var repo: SeerrRepositoryProtocol { container.seerrRepository }
    private var seerrCapabilityAvailable: Bool {
        container.pluginSyncService.isPluginAvailable || seerrEnabled
    }

    var body: some View {
        SettingsScreenLayout(title: "Seerr") {
            if seerrCapabilityAvailable {
                SettingsToggleButton(
                    icon: "film",
                    heading: "Enable Seerr",
                    caption: "Enable Seerr integration in app navigation",
                    isOn: seerrEnabledBinding
                )
            }

            if seerrEnabled {
                if !isAuthenticated {
                    SettingsListButton(
                        icon: "person.crop.circle",
                        heading: "Account Type",
                        caption: "Choose authentication method",
                        trailingText: authType.displayName,
                        action: { authType = authType == .jellyfin ? .local : .jellyfin }
                    )

                    SeerrTextInputField(
                        title: authType == .local ? "Email" : "Username",
                        text: $usernameOrEmail,
                        icon: "person"
                    )

                    SeerrTextInputField(
                        title: "Password",
                        text: $password,
                        icon: "key"
                    )

                    SettingsListButton(
                        icon: "arrow.right.circle",
                        heading: "Sign In",
                        caption: "Authenticate with your Seerr account",
                        action: { Task { await signIn() } }
                    )
                } else {
                    SettingsListButton(
                        icon: "rectangle.portrait.and.arrow.right",
                        heading: "Sign Out",
                        caption: "Sign out of your Seerr account",
                        action: { Task { await signOut() } }
                    )

                    SettingsToggleButton(
                        icon: "eye.slash",
                        heading: "Block NSFW",
                        caption: "Filter adult content from results",
                        isOn: blockNsfwBinding
                    )

                    SettingsListButton(
                        icon: "number",
                        heading: "Fetch Limit",
                        caption: "Items per page",
                        trailingText: fetchLimit.displayName,
                        action: { settingsRouter.navigate(to: .seerrFetchLimit) }
                    )
                    .focused($focusedRoute, equals: .seerrFetchLimit)

                    SettingsToggleButton(
                        icon: "sidebar.leading",
                        heading: "Show in Navigation",
                        caption: "Show Seerr in the sidebar",
                        isOn: showInNavigationBinding
                    )

                    SettingsToggleButton(
                        icon: "rectangle.topthird.inset.filled",
                        heading: "Show in Toolbar",
                        caption: "Show Seerr button in toolbar",
                        isOn: showInToolbarBinding
                    )

                    SettingsToggleButton(
                        icon: "checkmark.circle",
                        heading: "Show Request Status",
                        caption: "Display request status on items",
                        isOn: showRequestStatusBinding
                    )

                    sectionDivider("Discover")

                    SettingsListButton(
                        icon: "list.bullet",
                        heading: "Discover Rows",
                        caption: "Configure visible rows and order",
                        action: { settingsRouter.navigate(to: .seerrRows) }
                    )
                    .focused($focusedRoute, equals: .seerrRows)
                }
            }

            if let authMessage {
                Text(authMessage)
                    .font(.caption)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            }
        }
        .task { await loadState() }
        .restoresFocus($focusedRoute)
    }

    // MARK: - Helpers

    private func sectionDivider(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.space2xs) {
            Divider()
                .background(theme.colorScheme.listCaption.opacity(0.3))
                .padding(.vertical, SpaceTokens.spaceXs)
            Text(title)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)
        }
    }

    // MARK: - Bindings

    private var blockNsfwBinding: Binding<Bool> {
        Binding(
            get: { blockNsfw },
            set: { newValue in
                blockNsfw = newValue
                let prefs = repo.getPreferences()
                prefs?[SeerrPreferences.blockNsfw] = newValue
            }
        )
    }

    private var showInNavigationBinding: Binding<Bool> {
        Binding(
            get: { showInNavigation },
            set: { newValue in
                showInNavigation = newValue
                let prefs = repo.getPreferences()
                prefs?[SeerrPreferences.showInNavigation] = newValue
            }
        )
    }

    private var showInToolbarBinding: Binding<Bool> {
        Binding(
            get: { showInToolbar },
            set: { newValue in
                showInToolbar = newValue
                let prefs = repo.getPreferences()
                prefs?[SeerrPreferences.showInToolbar] = newValue
            }
        )
    }

    private var showRequestStatusBinding: Binding<Bool> {
        Binding(
            get: { showRequestStatus },
            set: { newValue in
                showRequestStatus = newValue
                let prefs = repo.getPreferences()
                prefs?[SeerrPreferences.showRequestStatus] = newValue
            }
        )
    }

    // MARK: - Actions

    private func loadState() async {
        await repo.ensureInitialized()
        let prefs = repo.getPreferences()
        seerrEnabled = prefs?[SeerrPreferences.enabled] ?? false
        fetchLimit = prefs?[SeerrPreferences.fetchLimit] ?? .medium
        blockNsfw = prefs?[SeerrPreferences.blockNsfw] ?? true
        showInNavigation = prefs?[SeerrPreferences.showInNavigation] ?? true
        showInToolbar = prefs?[SeerrPreferences.showInToolbar] ?? true
        showRequestStatus = prefs?[SeerrPreferences.showRequestStatus] ?? true
        let method = prefs?[SeerrPreferences.authMethod] ?? ""
        authType = method.contains("local") ? .local : .jellyfin
        usernameOrEmail = prefs?[SeerrPreferences.localEmail] ?? ""
        password = prefs?[SeerrPreferences.localPassword] ?? ""
        isAuthenticated = await repo.isSessionValidCached()
    }

    private var seerrEnabledBinding: Binding<Bool> {
        Binding(
            get: { seerrEnabled },
            set: { newValue in
                seerrEnabled = newValue
                let prefs = repo.getPreferences()
                prefs?[SeerrPreferences.enabled] = newValue
                if !newValue {
                    Task {
                        await repo.logout()
                        isAuthenticated = false
                    }
                }
            }
        )
    }

    private func signIn() async {
        guard let prefs = repo.getPreferences() else { return }
        let seerrUrl = prefs[SeerrPreferences.serverUrl]
        guard !seerrUrl.isEmpty else {
            authMessage = "Set Seerr server URL first in integration config"
            return
        }

        do {
            switch authType {
            case .jellyfin:
                guard let session = repo.getJellyfinSessionInfo() else {
                    authMessage = "No active Jellyfin session found"
                    return
                }
                _ = try await repo.loginWithJellyfin(
                    username: usernameOrEmail,
                    password: password,
                    jellyfinUrl: session.serverUrl,
                    seerrUrl: seerrUrl
                )
            case .local:
                _ = try await repo.loginLocal(
                    email: usernameOrEmail,
                    password: password,
                    seerrUrl: seerrUrl
                )
            }

            authMessage = "Signed in"
            isAuthenticated = true
        } catch {
            authMessage = "Sign in failed"
            isAuthenticated = false
        }
    }

    private func signOut() async {
        await repo.logout()
        isAuthenticated = false
        authMessage = "Signed out"
    }
}

private enum SeerrAuthType {
    case jellyfin
    case local

    var displayName: String {
        switch self {
        case .jellyfin: return "Jellyfin"
        case .local: return "Local"
        }
    }
}

private struct SeerrTextInputField: View {
    let title: String
    @Binding var text: String
    let icon: String

    @EnvironmentObject private var theme: MoonfinTheme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            Image(systemName: icon)
                .font(.bodyLg)
                .foregroundColor(focused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listOverline)
                .frame(width: 36)

            TextField(title, text: $text)
                .font(.bodyMd)
                .foregroundColor(focused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($focused)
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                .fill(focused ? theme.colorScheme.listButtonFocused : theme.colorScheme.listButton)
        )
    }
}
