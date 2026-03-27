import SwiftUI

struct SettingsScreenLayout<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var settingsRouter: SettingsRouter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                Text(title)
                    .font(.titleXl)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .padding(.horizontal, SpaceTokens.spaceMd)
                    .padding(.top, SpaceTokens.spaceLg)
                    .padding(.bottom, SpaceTokens.spaceSm)

                content()
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.bottom, SpaceTokens.spaceLg)
        }
        .onExitCommand {
            settingsRouter.goBack()
        }
    }
}
