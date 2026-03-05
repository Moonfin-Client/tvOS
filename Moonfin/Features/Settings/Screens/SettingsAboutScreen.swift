import SwiftUI

struct SettingsAboutScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
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
        }
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
