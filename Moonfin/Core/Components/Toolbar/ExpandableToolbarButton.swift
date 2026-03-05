import SwiftUI

struct ExpandableToolbarButton: View {
    let icon: String
    let label: String
    var isAssetIcon: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpaceTokens.spaceSm) {
                if isAssetIcon {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                }

                if isFocused {
                    Text(label)
                        .font(.bodySm)
                        .fontWeight(.bold)
                        .padding(.trailing, 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .padding(.horizontal, isFocused ? 16 : 8)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isFocused ? theme.focusBorder.color : .clear)
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
