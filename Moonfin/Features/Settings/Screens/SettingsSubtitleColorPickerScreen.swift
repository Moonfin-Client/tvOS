import SwiftUI

struct SettingsSubtitleColorPickerScreen: View {
    let title: String
    let preference: Preference<SubtitleColor>

    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var current: SubtitleColor {
        container.userPreferences[preference]
    }

    var body: some View {
        SettingsScreenLayout(title: title) {
            ForEach(SubtitleColor.allCases, id: \.self) { color in
                Button {
                    container.userPreferences[preference] = color
                    settingsRouter.goBack()
                } label: {
                    SubtitleColorOptionContent(
                        color: color,
                        isSelected: current == color
                    )
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
    }
}

private struct SubtitleColorOptionContent: View {
    let color: SubtitleColor
    let isSelected: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            Circle()
                .fill(color.isTransparent ? .clear : color.swiftUIColor)
                .overlay(
                    Circle()
                        .stroke(
                            isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listCaption,
                            lineWidth: color.isTransparent ? 2 : 0
                        )
                )
                .overlay {
                    if color.isTransparent {
                        Image(systemName: "line.diagonal")
                            .font(.caption)
                            .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listCaption)
                    }
                }
                .frame(width: 24, height: 24)

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
