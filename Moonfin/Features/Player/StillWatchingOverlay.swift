import SwiftUI

struct StillWatchingOverlay: View {
    let onContinue: () -> Void
    let onStop: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: SpaceTokens.spaceLg) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 56))
                    .foregroundColor(theme.accent)

                Text("Still Watching?")
                    .font(.title2xl)
                    .foregroundColor(.white)

                Text("You've been watching for a while")
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.listCaption)

                HStack(spacing: SpaceTokens.spaceMd) {
                    actionButton(label: "Continue", icon: "play.fill", isAccent: true, action: onContinue)
                    actionButton(label: "Stop", icon: "stop.fill", isAccent: false, action: onStop)
                }
                .padding(.top, SpaceTokens.spaceMd)
            }
            .padding(SpaceTokens.space3xl)
        }
        .transition(.opacity)
    }

    private func actionButton(label: String, icon: String, isAccent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: icon)
                Text(label)
                    .fontWeight(.semibold)
            }
            .font(.bodyMd)
            .padding(.horizontal, SpaceTokens.spaceLg)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(isAccent ? theme.accent.opacity(0.85) : theme.colorScheme.surface.opacity(0.7))
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
}
