import SwiftUI

struct SettingsToggleButton: View {
    let icon: String
    let heading: String
    var caption: String? = nil
    @Binding var isOn: Bool
    @State private var visualIsOn: Bool

    @EnvironmentObject var theme: MoonfinTheme

    init(icon: String, heading: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.icon = icon
        self.heading = heading
        self.caption = caption
        _isOn = isOn
        _visualIsOn = State(initialValue: isOn.wrappedValue)
    }

    var body: some View {
        Button {
            let next = !isOn
            visualIsOn = next
            isOn = next
        } label: {
            SettingsItemContent(icon: icon, heading: heading, caption: caption) { isFocused in
                Image(systemName: visualIsOn ? "checkmark.circle.fill" : "circle")
                    .font(.bodyLg)
                    .foregroundColor(visualIsOn
                        ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                        : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
            }
        }
        .buttonStyle(CleanButtonStyle())
        .onChange(of: isOn) { newValue in
            visualIsOn = newValue
        }
    }
}
