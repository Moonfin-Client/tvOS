import SwiftUI

struct GridButtonCard: View {
    let title: String
    let icon: String
    var width: CGFloat = 110

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(isFocused ? theme.colorScheme.onBackground : theme.colorScheme.onBackground.opacity(0.7))
                .frame(width: width, height: width)

            Text(title)
                .font(.captionXs)
                .foregroundColor(isFocused ? theme.colorScheme.onBackground : theme.colorScheme.onBackground.opacity(0.7))
                .lineLimit(1)
                .padding(.horizontal, SpaceTokens.spaceXs)
                .padding(.bottom, SpaceTokens.spaceSm)
        }
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                .fill(isFocused ? theme.colorScheme.surface : theme.colorScheme.surface.opacity(0.4))
        )
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.extraSmall))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .focusable()
        .focused($isFocused)
    }
}
