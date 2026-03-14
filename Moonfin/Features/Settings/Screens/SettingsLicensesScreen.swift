import SwiftUI

struct LicenseEntry: Codable, Identifiable {
    let artifactId: String
    let name: String
    let version: String
    let license: String
    let licenseText: String

    var id: String { artifactId }
}

struct SettingsLicensesScreen: View {
    @EnvironmentObject var settingsRouter: SettingsRouter

    @State private var licenses: [LicenseEntry] = []

    var body: some View {
        SettingsScreenLayout(title: "Licenses") {
            ForEach(licenses) { entry in
                SettingsListButton(
                    icon: "doc.text",
                    heading: entry.name,
                    caption: entry.license,
                    trailingText: entry.version,
                    action: { settingsRouter.navigate(to: .license(artifactId: entry.artifactId)) }
                )
            }
        }
        .onAppear { loadLicenses() }
    }

    private func loadLicenses() {
        guard licenses.isEmpty,
              let url = Bundle.main.url(forResource: "licenses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([LicenseEntry].self, from: data) else { return }
        licenses = decoded
    }
}
