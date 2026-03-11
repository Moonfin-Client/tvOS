import SwiftUI

struct SettingsSyncPlayValueScreen: View {
    let title: String
    let preference: Preference<Int>
    let options: [Int]
    let suffix: String

    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme

    private var currentValue: Int {
        container.userPreferences[preference]
    }

    var body: some View {
        SettingsScreenLayout(title: title) {
            ForEach(options, id: \.self) { value in
                Button {
                    container.userPreferences[preference] = value
                    settingsRouter.goBack()
                } label: {
                    SyncPlayValueOptionContent(
                        text: "\(value)\(suffix)",
                        isSelected: currentValue == value
                    )
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
    }
}

private struct SyncPlayValueOptionContent: View {
    let text: String
    let isSelected: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            Text(text)
                .font(.bodyMd)
                .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)

            Spacer()

            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.bodyMd)
                .foregroundColor(isSelected
                    ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                    : theme.colorScheme.listCaption)
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
    }
}
