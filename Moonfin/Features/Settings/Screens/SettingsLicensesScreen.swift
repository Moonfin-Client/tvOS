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
    @FocusState private var focusedArtifactId: String?

    @State private var licenses: [LicenseEntry] = []

    var body: some View {
        SettingsScreenLayout(title: Strings.licenses) {
            SettingsListButton(
                icon: "chevron.left",
                heading: Strings.back,
                action: { settingsRouter.goBack() }
            )

            if licenses.isEmpty {
                Text(Strings.noLicensesFound)
                    .font(.bodyMd)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceLg)
            } else {
                ForEach(licenses) { entry in
                    SettingsListButton(
                        icon: "doc.text",
                        heading: entry.name,
                        caption: entry.license,
                        trailingText: entry.version,
                        action: { settingsRouter.navigate(to: .license(artifactId: entry.artifactId)) }
                    )
                    .focused($focusedArtifactId, equals: entry.artifactId)
                }
            }
        }
        .onAppear { loadLicenses() }
        .onAppear {
            guard let route = settingsRouter.lastPoppedRoute,
                  case .license(let artifactId) = route else { return }
            settingsRouter.lastPoppedRoute = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    focusedArtifactId = artifactId
                }
            }
        }
    }

    private func loadLicenses() {
        guard licenses.isEmpty,
              let url = Bundle.main.url(forResource: "licenses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([LicenseEntry].self, from: data) else { return }
        licenses = decoded
    }
}
