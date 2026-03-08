import SwiftUI

struct CleanButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct FocusableDialogButton: View {
    let title: String
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bodyMd)
                .fontWeight(.medium)
                .foregroundColor(isFocused ? .black : theme.colorScheme.onBackground)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.vertical, SpaceTokens.spaceSm)
                .background(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .fill(isFocused ? Color.white : Color.white.opacity(0.1))
                )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}
