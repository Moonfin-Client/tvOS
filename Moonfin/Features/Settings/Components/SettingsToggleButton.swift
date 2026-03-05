import SwiftUI

struct SettingsToggleButton: View {
    let icon: String
    let heading: String
    var caption: String? = nil
    @Binding var isOn: Bool

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button { isOn.toggle() } label: {
            SettingsItemContent(icon: icon, heading: heading, caption: caption) { isFocused in
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.bodyLg)
                    .foregroundColor(isOn
                        ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                        : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
            }
        }
        .buttonStyle(CleanButtonStyle())
    }
}
