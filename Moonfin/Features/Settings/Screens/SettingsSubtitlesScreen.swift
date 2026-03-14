import SwiftUI

struct SettingsSubtitlesScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Subtitles") {
            SubtitlePreview(
                textColor: prefs[UserPreferences.subtitlesTextColor],
                backgroundColor: prefs[UserPreferences.subtitlesBackgroundColor],
                strokeColor: prefs[UserPreferences.subtitlesStrokeColor],
                textSize: prefs[UserPreferences.subtitlesTextSize]
            )

            SettingsListButton(
                icon: "textformat",
                heading: "Text Color",
                caption: prefs[UserPreferences.subtitlesTextColor].displayName,
                action: { settingsRouter.navigate(to: .customizationSubtitlesTextColor) }
            ) 

            SettingsListButton(
                icon: "rectangle.fill",
                heading: "Background Color",
                caption: prefs[UserPreferences.subtitlesBackgroundColor].displayName,
                action: { settingsRouter.navigate(to: .customizationSubtitlesBackgroundColor) }
            )

            SettingsListButton(
                icon: "square.dashed",
                heading: "Edge Color",
                caption: prefs[UserPreferences.subtitlesStrokeColor].displayName,
                action: { settingsRouter.navigate(to: .customizationSubtitlesEdgeColor) }
            )

            SettingsListButton(
                icon: "textformat.size",
                heading: "Text Size",
                caption: "Font size for subtitles",
                trailingText: "\(prefs[UserPreferences.subtitlesTextSize])pt",
                action: { settingsRouter.navigate(to: .customizationSubtitlesTextSize) }
            )

            SettingsListButton(
                icon: "arrow.up.and.down",
                heading: "Offset Position",
                caption: "Distance from bottom edge",
                trailingText: "\(prefs[UserPreferences.subtitlesOffsetPosition])%",
                action: { settingsRouter.navigate(to: .customizationSubtitlesOffset) }
            )

            SettingsToggleButton(
                icon: "captions.bubble",
                heading: "Default to None",
                caption: "Start playback without subtitles",
                isOn: prefs.binding(for: UserPreferences.subtitlesDefaultToNone)
            )
        }
    }
}

private struct SubtitlePreview: View {
    let textColor: SubtitleColor
    let backgroundColor: SubtitleColor
    let strokeColor: SubtitleColor
    let textSize: Int

    @EnvironmentObject var theme: MoonfinTheme

    private var previewFontSize: CGFloat {
        CGFloat(max(14, min(textSize, 32)))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .frame(height: 120)

            Text("Sample Subtitle Text")
                .font(.system(size: previewFontSize, weight: .medium))
                .foregroundColor(textColor.swiftUIColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(backgroundColor.swiftUIColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(strokeColor.isTransparent ? .clear : strokeColor.swiftUIColor, lineWidth: 2)
                )
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.bottom, SpaceTokens.spaceSm)
    }
}
