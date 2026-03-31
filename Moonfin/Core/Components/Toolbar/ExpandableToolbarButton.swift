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
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 26))
                }

                Text(label)
                    .font(.bodyMd)
                    .fontWeight(.bold)
                    .padding(.trailing, 4)
                    .opacity(isFocused ? 1.0 : 0.0)
                    .frame(width: isFocused ? nil : 0, alignment: .center)
                    .clipped()
            }
            .padding(.horizontal, isFocused ? 20 : 10)
            .padding(.vertical, 12)
            .foregroundColor(isFocused ? theme.focusBorder.color.contrastingContentColor : theme.colorScheme.onButton)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isFocused)
    }
}
