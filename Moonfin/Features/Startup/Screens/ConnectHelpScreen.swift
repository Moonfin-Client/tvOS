import SwiftUI

struct ConnectHelpScreen: View {
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()

            HStack(spacing: SpaceTokens.space3xl) {
                VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
                    Text("Getting Started")
                        .font(.token(45, weight: .bold))
                        .foregroundColor(theme.colorScheme.onBackground)

                    Text("To use Moonfin, you need a Jellyfin or Emby media server running on your network or accessible via the internet.\n\nEnter your server's address (e.g. https://your-server.com) on the previous screen to connect.\n\nVisit jellyfin.org for setup instructions.")
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                        .lineSpacing(4)

                    Button {
                        router.goBack()
                    } label: {
                        HStack(spacing: SpaceTokens.spaceXs) {
                            Image(systemName: "checkmark")
                            Text("Got it")
                        }
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.onButtonFocused)
                        .padding(.horizontal, SpaceTokens.spaceLg)
                        .padding(.vertical, SpaceTokens.spaceSm)
                        .background(
                            RoundedRectangle(cornerRadius: RadiusTokens.small)
                                .fill(theme.colorScheme.buttonFocused)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, SpaceTokens.spaceSm)
                }
                .frame(maxWidth: 400)

                Image(systemName: "qrcode")
                    .font(.system(size: 150))
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
            }
            .padding(SpaceTokens.space3xl)
        }
    }
}
