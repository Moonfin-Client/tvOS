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
            Text(Strings.currentValue("\(currentValue)\(suffix)"))
                .font(.captionSm)
                .foregroundColor(theme.colorScheme.listCaption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.bottom, SpaceTokens.space2xs)

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
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                .fill(isFocused ? theme.colorScheme.listButtonFocused : theme.colorScheme.listButton)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
