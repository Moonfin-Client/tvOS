import SwiftUI

struct SettingsListButton: View {
    let icon: String
    let heading: String
    var caption: String? = nil
    var trailingText: String? = nil
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            SettingsItemContent(icon: icon, heading: heading, caption: caption) { isFocused in
                if let trailingText {
                    Text(trailingText)
                        .font(.captionXs)
                        .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
                }

                Image(systemName: "chevron.right")
                    .font(.captionXs)
                    .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused.opacity(0.5) : theme.colorScheme.listCaption)
            }
        }
        .buttonStyle(CleanButtonStyle())
    }
}
