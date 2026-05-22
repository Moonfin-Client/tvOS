import SwiftUI

struct SettingsSeerrScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedRoute: SettingsRoute?

    @State private var fetchLimit: SeerrFetchLimit = .medium
    @State private var seerrEnabled = false
    @State private var isAuthenticated = false
    @State private var seerrStatus: MoonfinStatusResponse?
    @State private var authType: SeerrAuthType = .jellyfin
    @State private var usernameOrEmail = ""
    @State private var password = ""
    @State private var authMessage: String?
    @State private var isSubmittingAuth = false
    @State private var blockNsfw = true
    @State private var showInNavigation = true
    @State private var showInToolbar = true
    @State private var showRequestStatus = true

    private var repo: SeerrRepositoryProtocol { container.seerrRepository }
    private var seerrCapabilityAvailable: Bool {
        container.pluginSyncService.isPluginAvailable || seerrEnabled
    }

    private var canSignIn: Bool {
        !isSubmittingAuth
            && !usernameOrEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private var signedInDisplayName: String? {
        if let name = seerrStatus?.displayName, !name.isEmpty {
            return name
        }

        let fallback = repo.getPreferences()?[SeerrPreferences.moonfinDisplayName] ?? ""
        return fallback.isEmpty ? nil : fallback
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
            } else {
                SettingsListButton(
                    icon: "chevron.left",
                    heading: "Back",
                    caption: "Return to Integrations",
                    action: { settingsRouter.goBack() }
                )

                Text("Seerr unavailable. Enable the server plugin and plugin sync first.")
                    .font(.caption)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceMd)
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

                    if isSubmittingAuth {
                        SettingsItemContent(
                            icon: "arrow.triangle.2.circlepath",
                            heading: "Signing In",
                            caption: "Authenticating with Seerr"
                        ) { _ in
                            ProgressView()
                        }
                    } else {
                        SettingsListButton(
                            icon: "arrow.right.circle",
                            heading: "Sign In",
                            caption: "Authenticate with your Seerr account",
                            action: { Task { await signIn() } }
                        )
                        .disabled(!canSignIn)
                        .opacity(canSignIn ? 1 : 0.6)
                    }
                } else {
                    if let signedInDisplayName {
                        SettingsItemContent(
                            icon: "person.crop.circle.badge.checkmark",
                            heading: "Signed In As",
                            caption: nil
                        ) { isFocused in
                            Text(signedInDisplayName)
                                .font(.captionXs)
                                .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
                        }
                    }

                    SettingsListButton(
                        icon: "rectangle.portrait.and.arrow.right",
                        heading: "Sign Out",
                        caption: "Sign out of your Seerr account",
                        action: { Task { await signOut() } }
                    )
                    .disabled(isSubmittingAuth)
                    .opacity(isSubmittingAuth ? 0.6 : 1)

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
        .onReceive(container.pluginSyncService.$isPluginAvailable.dropFirst()) { _ in
            Task { await loadState() }
        }
        .onReceive(container.pluginSyncService.$syncCompletedCount.dropFirst()) { _ in
            Task { await loadState() }
        }
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

    private func ensureMoonfinProxyConfigured(showError: Bool) async -> Bool {
        if repo.isMoonfinMode.value {
            return true
        }

        guard let session = container.sessionRepository.currentSession.value,
              let server = container.serverRepository.currentServer.value else {
            if showError {
                authMessage = "No active Jellyfin session found"
            }
            return false
        }

        let jellyfinBaseUrl = server.address.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !jellyfinBaseUrl.isEmpty, !session.accessToken.isEmpty else {
            if showError {
                authMessage = "No active Jellyfin session found"
            }
            return false
        }

        do {
            seerrStatus = try await repo.configureWithMoonfin(
                jellyfinBaseUrl: jellyfinBaseUrl,
                jellyfinToken: session.accessToken
            )
            return true
        } catch {
            if showError {
                authMessage = extractSeerrAuthError(error)
            }
            return false
        }
    }

    private func extractSeerrAuthError(_ error: Error) -> String {
        if let seerrError = error as? SeerrError {
            switch seerrError {
            case .moonfinLoginFailed(let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            return seerrError.localizedDescription
        }

        if let networkError = error as? NetworkError {
            switch networkError {
            case .httpError(_, let data):
                return parseSeerrErrorPayload(data) ?? networkError.localizedDescription
            default:
                return networkError.localizedDescription
            }
        }

        return error.localizedDescription
    }

    private func parseSeerrErrorPayload(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let nested = json["error"] as? [String: Any],
               let message = (nested["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return message
            }

            let candidateKeys = ["error", "message", "detail", "reason", "title"]
            for key in candidateKeys {
                if let message = (json[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !message.isEmpty {
                    return message
                }
            }

            if let errors = json["errors"] as? [String],
               let first = errors.first?.trimmingCharacters(in: .whitespacesAndNewlines),
               !first.isEmpty {
                return first
            }
        }

        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }

        return nil
    }

    private func refreshMoonfinStatus() async {
        do {
            seerrStatus = try await repo.checkMoonfinStatus()
            isAuthenticated = seerrStatus?.authenticated == true
            seerrEnabled = repo.getPreferences()?[SeerrPreferences.enabled] ?? seerrEnabled
        } catch {
            seerrStatus = nil
            isAuthenticated = false
        }
    }

    private func performMoonfinSignOut(showMessage: Bool) async {
        await repo.logoutMoonfin()
        password = ""
        seerrStatus = nil
        isAuthenticated = false
        seerrEnabled = repo.getPreferences()?[SeerrPreferences.enabled] ?? false
        authMessage = showMessage ? "Signed out" : nil
        await container.pluginSyncService.syncOnStartup()
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

    private var seerrEnabledBinding: Binding<Bool> {
        Binding(
            get: { seerrEnabled },
            set: { newValue in
                seerrEnabled = newValue
                let prefs = repo.getPreferences()
                prefs?[SeerrPreferences.enabled] = newValue

                if !newValue {
                    Task {
                        await performMoonfinSignOut(showMessage: false)
                    }
                }
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
        password = ""

        if seerrEnabled {
            _ = await ensureMoonfinProxyConfigured(showError: false)
            await refreshMoonfinStatus()
        } else {
            seerrStatus = nil
            isAuthenticated = false
        }
    }

    private func signIn() async {
        guard canSignIn else { return }

        isSubmittingAuth = true
        authMessage = nil
        defer { isSubmittingAuth = false }

        guard await ensureMoonfinProxyConfigured(showError: true) else {
            isAuthenticated = false
            return
        }

        let username = usernameOrEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let response = try await repo.loginWithMoonfin(
                username: username,
                password: password,
                authType: authType.apiValue
            )

            guard response.success else {
                authMessage = response.error ?? "Sign in failed"
                isAuthenticated = false
                return
            }

            let prefs = repo.getPreferences()
            prefs?[SeerrPreferences.authMethod] = authType.apiValue
            prefs?[SeerrPreferences.localEmail] = username
            if let displayName = response.displayName, !displayName.isEmpty {
                prefs?[SeerrPreferences.moonfinDisplayName] = displayName
            }

            password = ""
            await refreshMoonfinStatus()
            await container.pluginSyncService.syncOnStartup()
            authMessage = "Signed in"
        } catch {
            authMessage = extractSeerrAuthError(error)
            isAuthenticated = false
        }
    }

    private func signOut() async {
        guard !isSubmittingAuth else { return }

        isSubmittingAuth = true
        authMessage = nil
        defer { isSubmittingAuth = false }

        await performMoonfinSignOut(showMessage: true)
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

    var apiValue: String {
        switch self {
        case .jellyfin: return "jellyfin"
        case .local: return "local"
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
