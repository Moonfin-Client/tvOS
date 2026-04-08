import SwiftUI

struct SettingsMediaSegmentScreen: View {
    let segmentType: MediaSegmentType
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var currentAction: MediaSegmentAction {
        let map = MediaSegmentRepositoryImpl.parseActionsString(
            container.userPreferences[UserPreferences.mediaSegmentActions]
        )
        return map[segmentType] ?? .nothing
    }

    private func setAction(_ action: MediaSegmentAction) {
        var map = MediaSegmentRepositoryImpl.parseActionsString(
            container.userPreferences[UserPreferences.mediaSegmentActions]
        )
        map[segmentType] = action
        container.userPreferences[UserPreferences.mediaSegmentActions] =
            MediaSegmentRepositoryImpl.actionsToString(map)
    }

    var body: some View {
        SettingsScreenLayout(title: segmentType.displayName) {
            ForEach(MediaSegmentAction.allCases, id: \.self) { action in
                PickerOptionRow(
                    label: action.displayName,
                    isSelected: currentAction == action
                ) {
                    setAction(action)
                    settingsRouter.goBack()
                }
            }
        }
    }
}

private struct PickerOptionRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpaceTokens.spaceMd) {
                Text(label)
                    .font(.bodyMd)
                    .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.bodyMd)
                    .foregroundColor(isSelected ? theme.accent : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                    .fill(isFocused ? theme.colorScheme.listButtonFocused : theme.colorScheme.listButton)
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(CleanButtonStyle())
    }
}
