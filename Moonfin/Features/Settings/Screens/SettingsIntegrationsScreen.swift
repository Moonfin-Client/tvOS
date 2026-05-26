import SwiftUI

struct SettingsIntegrationsScreen: View {
    @FocusState private var focusedRoute: SettingsRoute?

    var body: some View {
        SettingsScreenLayout(title: "Integrations") {
            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .plugin,
                icon: "puzzlepiece.extension",
                heading: "Plugin",
                caption: "Plugin sync status and settings"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .integrationsMetadataRatings,
                icon: "star.fill",
                heading: "Metadata and Ratings",
                caption: "Additional rating provider settings"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .seerr,
                icon: "asset:settings-seerr",
                heading: "Seerr",
                caption: "Seerr integration settings"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .integrationsHomeScreenSections,
                icon: "asset:settings-hss",
                heading: "Home Screen Sections",
                caption: "Integration status and linked sections"
            )
        }
        .restoresFocus($focusedRoute)
    }
}

struct SettingsHomeScreenSectionsIntegrationScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    @FocusState private var focusedRoute: SettingsRoute?
    @State private var refreshTrigger = 0
    @State private var statusText: String?

    private var capability: HomeScreenSectionsCapability? {
        container.homeScreenSectionsService.activeCapability
    }

    var body: some View {
        SettingsScreenLayout(title: "Home Screen Sections") {
            let _ = refreshTrigger

            HomeSectionsStatusRow(
                icon: "server.rack",
                heading: "Active Server",
                caption: activeServerAddress,
                value: activeServerName
            )

            HomeSectionsStatusRow(
                icon: "puzzlepiece.extension",
                heading: "Plugin Status",
                caption: "Detected from plugin and meta probes",
                value: pluginStatusText
            )

            HomeSectionsStatusRow(
                icon: "number",
                heading: "Discovered Sections",
                caption: "Rows discovered for the active server",
                value: "\(capability?.sections.count ?? 0)"
            )

            HomeSectionsStatusRow(
                icon: "tag",
                heading: "Plugin Version",
                caption: "Reported by installed plugins API",
                value: capability?.pluginVersion ?? "Unknown"
            )

            HomeSectionsStatusRow(
                icon: "clock",
                heading: "Last Updated",
                caption: "Latest capability refresh time",
                value: formattedLastUpdated
            )

            if let errorText = capability?.lastErrorDescription, !errorText.isEmpty {
                HomeSectionsStatusRow(
                    icon: "exclamationmark.triangle",
                    heading: "Last Error",
                    caption: "Most recent probe error",
                    value: errorText
                )
            }

            SettingsListButton(
                icon: "arrow.clockwise",
                heading: "Refresh Status",
                caption: "Re-run capability and section discovery now",
                action: {
                    Task {
                        await container.homeScreenSectionsService.refreshActiveServerNow()
                        statusText = "Status refreshed"
                        refreshTrigger += 1
                    }
                }
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .homeSections,
                icon: "list.bullet",
                heading: "Manage Home Sections",
                caption: "Open row enablement and ordering"
            )

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            }
        }
        .onAppear {
            container.homeScreenSectionsService.requestRefresh()
        }
        .onReceive(container.homeScreenSectionsService.$refreshCompletedCount) { _ in
            refreshTrigger += 1
        }
        .onReceive(container.pluginSyncService.$syncCompletedCount.dropFirst()) { _ in
            container.homeScreenSectionsService.requestRefresh()
        }
        .restoresFocus($focusedRoute)
    }

    private var activeServerName: String {
        container.serverRepository.currentServer.value?.name ?? "Not Connected"
    }

    private var activeServerAddress: String? {
        container.serverRepository.currentServer.value?.address
    }

    private var pluginStatusText: String {
        guard let capability else { return "Unknown" }
        if !capability.installed { return "Not Installed" }
        return capability.enabled ? "Installed, Enabled" : "Installed, Disabled"
    }

    private var formattedLastUpdated: String {
        guard let updatedAt = capability?.lastUpdatedAt else { return "Never" }
        return Self.dateFormatter.string(from: updatedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct HomeSectionsStatusRow: View {
    let icon: String
    let heading: String
    let caption: String?
    let value: String

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        SettingsItemContent(icon: icon, heading: heading, caption: caption) { isFocused in
            Text(value)
                .font(.captionXs)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
        }
    }
}
