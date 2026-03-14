import SwiftUI

struct SettingsSeerrScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme

    @State private var isEnabled = false
    @State private var serverUrl = ""
    @State private var authStatus = ""
    @State private var authMethod = ""
    @State private var fetchLimit: SeerrFetchLimit = .medium
    @State private var blockNsfw = true
    @State private var showInNavigation = true
    @State private var showInToolbar = true
    @State private var showRequestStatus = true
    @State private var isConnected = false
    @State private var statusMessage = ""

    @State private var showUrlAlert = false
    @State private var urlInput = ""
    @State private var showJellyfinAlert = false
    @State private var jellyfinPassword = ""
    @State private var showLocalAlert = false
    @State private var localEmail = ""
    @State private var localPassword = ""
    @State private var showApiKeyAlert = false
    @State private var apiKeyInput = ""
    @State private var showLogoutConfirm = false

    private var repo: SeerrRepositoryProtocol { container.seerrRepository }

    var body: some View {
        SettingsScreenLayout(title: "Jellyseerr") {
            SettingsToggleButton(
                icon: "film",
                heading: "Enable Jellyseerr",
                caption: "Media request management",
                isOn: enabledBinding
            )

            sectionDivider("Connection")

            serverUrlButton
            connectionStatusView

            sectionDivider("Authentication")

            authStatusView
            jellyfinSignInButton
            localSignInButton
            apiKeyButton

            if isConnected {
                logoutButton
            }

            sectionDivider("Content")

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

            SettingsToggleButton(
                icon: "sidebar.leading",
                heading: "Show in Navigation",
                caption: "Show Jellyseerr in the sidebar",
                isOn: showInNavigationBinding
            )

            SettingsToggleButton(
                icon: "rectangle.topthird.inset.filled",
                heading: "Show in Toolbar",
                caption: "Show Jellyseerr button in toolbar",
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
        }
        .task { await loadState() }
        .alert("Server URL", isPresented: $showUrlAlert) {
            TextField("https://jellyseerr.example.com", text: $urlInput)
            Button("Save") { saveServerUrl() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Sign in with Jellyfin", isPresented: $showJellyfinAlert) {
            SecureField("Password", text: $jellyfinPassword)
            Button("Sign In") { signInWithJellyfin() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let info = repo.getJellyfinSessionInfo() {
                Text("Signing in as \(info.username)")
            }
        }
        .alert("Sign in with Local Account", isPresented: $showLocalAlert) {
            TextField("Email", text: $localEmail)
            SecureField("Password", text: $localPassword)
            Button("Sign In") { signInWithLocal() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Enter API Key", isPresented: $showApiKeyAlert) {
            TextField("API Key", text: $apiKeyInput)
            Button("Save") { signInWithApiKey() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Logout", isPresented: $showLogoutConfirm) {
            Button("Logout", role: .destructive) { performLogout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to log out of Jellyseerr?")
        }
    }

    // MARK: - Subviews

    private var serverUrlButton: some View {
        SettingsListButton(
            icon: "link",
            heading: "Server URL",
            caption: serverUrl.isEmpty ? "Not configured" : serverUrl,
            action: {
                urlInput = serverUrl
                showUrlAlert = true
            }
        )
    }

    private var connectionStatusView: some View {
        Group {
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.captionXs)
                    .foregroundColor(isConnected ? .green : theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceSm)
            }
        }
    }

    private var authStatusView: some View {
        Group {
            if !authStatus.isEmpty {
                HStack(spacing: SpaceTokens.spaceXs) {
                    Image(systemName: isConnected ? "checkmark.shield.fill" : "xmark.shield")
                        .foregroundColor(isConnected ? .green : theme.colorScheme.listCaption)
                    Text(authStatus)
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.onBackground)
                }
                .padding(.horizontal, SpaceTokens.spaceSm)
                .padding(.vertical, SpaceTokens.space2xs)
            }
        }
    }

    private var jellyfinSignInButton: some View {
        Group {
            if !isConnected {
                SettingsListButton(
                    icon: "person.crop.circle",
                    heading: "Sign in with Jellyfin",
                    caption: repo.getJellyfinSessionInfo().map { "As \($0.username)" },
                    action: {
                        jellyfinPassword = ""
                        showJellyfinAlert = true
                    }
                )
            }
        }
    }

    private var localSignInButton: some View {
        Group {
            if !isConnected {
                SettingsListButton(
                    icon: "envelope",
                    heading: "Sign in with Local Account",
                    action: {
                        localEmail = ""
                        localPassword = ""
                        showLocalAlert = true
                    }
                )
            }
        }
    }

    private var apiKeyButton: some View {
        Group {
            if !isConnected {
                SettingsListButton(
                    icon: "key",
                    heading: "Enter API Key",
                    action: {
                        apiKeyInput = ""
                        showApiKeyAlert = true
                    }
                )
            }
        }
    }

    private var logoutButton: some View {
        Button(action: { showLogoutConfirm = true }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Logout")
            }
            .font(.bodyMd)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.top, SpaceTokens.spaceSm)
        }
        .buttonStyle(CleanButtonStyle())
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

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                isEnabled = newValue
                let prefs = repo.getPreferences()
                prefs?[SeerrPreferences.enabled] = newValue
            }
        )
    }

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
        isEnabled = prefs?[SeerrPreferences.enabled] ?? false
        serverUrl = prefs?[SeerrPreferences.serverUrl] ?? ""
        authMethod = prefs?[SeerrPreferences.authMethod] ?? ""
        fetchLimit = prefs?[SeerrPreferences.fetchLimit] ?? .medium
        blockNsfw = prefs?[SeerrPreferences.blockNsfw] ?? true
        showInNavigation = prefs?[SeerrPreferences.showInNavigation] ?? true
        showInToolbar = prefs?[SeerrPreferences.showInToolbar] ?? true
        showRequestStatus = prefs?[SeerrPreferences.showRequestStatus] ?? true
        isConnected = repo.isAvailable.value
        updateAuthStatus()
    }

    private func updateAuthStatus() {
        if !isConnected {
            authStatus = "Not authenticated"
            return
        }
        switch authMethod {
        case "jellyfin", "jellyfin-apikey":
            let username = repo.getJellyfinSessionInfo()?.username ?? "Unknown"
            authStatus = "Signed in as \(username)"
        case "local", "local-apikey":
            authStatus = "Local account active"
        case "apikey":
            authStatus = "API key active"
        case "moonfin":
            authStatus = "Moonfin proxy active"
        default:
            authStatus = isConnected ? "Connected" : "Not authenticated"
        }
    }

    private func saveServerUrl() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        serverUrl = trimmed
        let prefs = repo.getPreferences()
        prefs?[SeerrPreferences.serverUrl] = trimmed
        statusMessage = trimmed.isEmpty ? "" : "URL saved"
    }

    private func signInWithJellyfin() {
        guard let info = repo.getJellyfinSessionInfo(), !serverUrl.isEmpty else {
            statusMessage = "Enter a server URL first"
            return
        }
        statusMessage = "Connecting..."
        Task {
            do {
                _ = try await repo.loginWithJellyfin(
                    username: info.username,
                    password: jellyfinPassword,
                    jellyfinUrl: info.serverUrl,
                    seerrUrl: serverUrl
                )
                isConnected = true
                isEnabled = true
                authMethod = "jellyfin"
                updateAuthStatus()
                statusMessage = "Connected"
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func signInWithLocal() {
        guard !serverUrl.isEmpty else {
            statusMessage = "Enter a server URL first"
            return
        }
        statusMessage = "Connecting..."
        Task {
            do {
                _ = try await repo.loginLocal(
                    email: localEmail,
                    password: localPassword,
                    seerrUrl: serverUrl
                )
                isConnected = true
                isEnabled = true
                authMethod = "local"
                updateAuthStatus()
                statusMessage = "Connected"
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func signInWithApiKey() {
        guard !serverUrl.isEmpty else {
            statusMessage = "Enter a server URL first"
            return
        }
        statusMessage = "Connecting..."
        Task {
            do {
                _ = try await repo.loginWithApiKey(
                    apiKey: apiKeyInput,
                    seerrUrl: serverUrl
                )
                isConnected = true
                isEnabled = true
                authMethod = "apikey"
                updateAuthStatus()
                statusMessage = "Connected"
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func performLogout() {
        Task {
            await repo.logout()
            isConnected = false
            authMethod = ""
            updateAuthStatus()
            statusMessage = "Logged out"
        }
    }
}
