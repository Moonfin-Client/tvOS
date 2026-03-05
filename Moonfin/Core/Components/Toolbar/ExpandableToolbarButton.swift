import SwiftUI

struct ExpandableToolbarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: icon)
                    .font(.system(size: 22))

                if isFocused {
                    Text(label)
                        .font(.bodySm)
                        .fontWeight(.bold)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .padding(.horizontal, isFocused ? 20 : 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isFocused ? theme.focusBorder.color : theme.colorScheme.button)
            )
            .foregroundColor(isFocused ? focusContentColor : theme.colorScheme.onButton)
        }
        .buttonStyle(CleanButtonStyle())
        .focusable()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    private var focusContentColor: Color {
        theme.focusBorder.color.contrastingContentColor
    }
}
