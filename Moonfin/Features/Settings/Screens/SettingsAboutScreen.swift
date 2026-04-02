import SwiftUI

struct SettingsAboutScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var body: some View {
        SettingsScreenLayout(title: "About") {
            aboutItem(label: "Version", value: appVersion)
            aboutItem(label: "Build", value: buildNumber)

            SettingsListButton(
                icon: "doc.text",
                heading: "Licenses",
                caption: "Open source licenses",
                action: { settingsRouter.navigate(to: .licenses) }
            )
            .focused($focusedRoute, equals: .licenses)
        }
        .restoresFocus($focusedRoute)
    }

    private func aboutItem(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.listHeadline)
            Spacer()
            Text(value)
                .font(.bodySm)
                .foregroundColor(theme.colorScheme.listCaption)
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
    }
}
