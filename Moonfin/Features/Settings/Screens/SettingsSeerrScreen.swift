import SwiftUI

struct SettingsSeerrScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedRoute: SettingsRoute?

    @State private var fetchLimit: SeerrFetchLimit = .medium
    @State private var blockNsfw = true
    @State private var showInNavigation = true
    @State private var showInToolbar = true
    @State private var showRequestStatus = true

    private var repo: SeerrRepositoryProtocol { container.seerrRepository }

    var body: some View {
        SettingsScreenLayout(title: "Seerr") {
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
        fetchLimit = prefs?[SeerrPreferences.fetchLimit] ?? .medium
        blockNsfw = prefs?[SeerrPreferences.blockNsfw] ?? true
        showInNavigation = prefs?[SeerrPreferences.showInNavigation] ?? true
        showInToolbar = prefs?[SeerrPreferences.showInToolbar] ?? true
        showRequestStatus = prefs?[SeerrPreferences.showRequestStatus] ?? true
    }
}
