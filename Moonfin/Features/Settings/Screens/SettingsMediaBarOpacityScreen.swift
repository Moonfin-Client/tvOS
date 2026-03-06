import SwiftUI

struct SettingsMediaBarOpacityScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme

    private var currentOpacity: Int {
        container.userPreferences[UserPreferences.mediaBarOverlayOpacity]
    }

    private let options = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

    var body: some View {
        SettingsScreenLayout(title: "Overlay Opacity") {
            ForEach(options, id: \.self) { value in
                Button {
                    container.userPreferences[UserPreferences.mediaBarOverlayOpacity] = value
                    settingsRouter.goBack()
                } label: {
                    OpacityOptionContent(
                        value: value,
                        isSelected: currentOpacity == value
                    )
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
    }
}

private struct OpacityOptionContent: View {
    let value: Int
    let isSelected: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            Text("\(value)%")
                .font(.bodyMd)
                .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)

            Spacer()

            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.bodyMd)
                .foregroundColor(isSelected
                    ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                    : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
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
