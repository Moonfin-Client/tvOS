import SwiftUI

struct SettingsLicenseDetailScreen: View {
    let artifactId: String

    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var settingsRouter: SettingsRouter

    @State private var entry: LicenseEntry?

    var body: some View {
        SettingsScreenLayout(title: entry?.name ?? Strings.licenseLabel) {
            SettingsListButton(
                icon: "chevron.left",
                heading: Strings.back,
                action: { settingsRouter.goBack() }
            )

            if let entry {
                VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                    HStack {
                        Text(entry.license)
                            .font(.bodyMd)
                            .foregroundColor(theme.colorScheme.listCaption)
                        Spacer()
                        Text("\(Strings.aboutVersion): \(entry.version)")
                            .font(.bodySm)
                            .foregroundColor(theme.colorScheme.listCaption)
                    }

                    Divider()
                        .background(theme.colorScheme.listCaption.opacity(0.3))

                    Text(entry.licenseText)
                        .font(.bodySm)
                        .foregroundColor(theme.colorScheme.onBackground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, SpaceTokens.spaceMd)
            }
        }
        .onAppear { loadEntry() }
    }

    private func loadEntry() {
        guard entry == nil,
              let url = Bundle.main.url(forResource: "licenses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([LicenseEntry].self, from: data) else { return }
        entry = decoded.first { $0.artifactId == artifactId }
    }
}
