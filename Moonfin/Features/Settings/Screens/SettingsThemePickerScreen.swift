import SwiftUI

struct SettingsThemePickerScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var settingsRouter: SettingsRouter

    var body: some View {
        SettingsScreenLayout(title: "Focus Border Color") {
            ForEach(FocusBorderColor.allCases) { color in
                ThemeColorButton(
                    color: color,
                    isSelected: theme.focusBorder == color
                ) {
                    theme.focusBorder = color
                    settingsRouter.goBack()
                }
            }
        }
    }
}

private struct ThemeColorButton: View {
    let color: FocusBorderColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ThemeColorContent(color: color, isSelected: isSelected)
        }
        .buttonStyle(CleanButtonStyle())
    }
}

private struct ThemeColorContent: View {
    let color: FocusBorderColor
    let isSelected: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            Circle()
                .fill(color.color)
                .frame(width: 20, height: 20)

            Text(color.displayName)
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
