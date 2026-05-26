import SwiftUI

struct SettingsItemContent<Trailing: View>: View {
    let icon: String
    let heading: String
    var caption: String?
    @ViewBuilder let trailing: (_ isFocused: Bool) -> Trailing

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    private var assetIconName: String? {
        let assetIconPrefix = "asset:"
        guard icon.hasPrefix(assetIconPrefix) else { return nil }
        let name = String(icon.dropFirst(assetIconPrefix.count))
        return name.isEmpty ? nil : name
    }

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            if let assetIconName {
                Image(assetIconName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .frame(width: 36)
            } else {
                Image(systemName: icon)
                    .font(.bodyLg)
                    .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listOverline)
                    .frame(width: 36)
            }

            VStack(alignment: .leading, spacing: SpaceTokens.space2xs) {
                Text(heading)
                    .font(.bodyMd)
                    .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)

                if let caption {
                    Text(caption)
                        .font(.captionXs)
                        .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
                }
            }

            Spacer()

            trailing(isFocused)
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                .fill(isFocused ? theme.colorScheme.listButtonFocused : theme.colorScheme.listButton)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
