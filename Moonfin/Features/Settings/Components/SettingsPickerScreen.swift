import SwiftUI

struct SettingsPickerScreen<T: Hashable & CaseIterable>: View where T.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: T
    let displayName: (T) -> String
    var options: [T]?

    @EnvironmentObject var settingsRouter: SettingsRouter

    var body: some View {
        SettingsScreenLayout(title: title) {
            ForEach(options ?? Array(T.allCases), id: \.self) { option in
                PickerOptionButton(
                    label: displayName(option),
                    isSelected: selection == option
                ) {
                    selection = option
                    settingsRouter.goBack()
                }
            }
        }
    }
}

private struct PickerOptionButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PickerOptionContent(label: label, isSelected: isSelected)
        }
        .buttonStyle(CleanButtonStyle())
    }
}

private struct PickerOptionContent: View {
    let label: String
    let isSelected: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            Text(label)
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
