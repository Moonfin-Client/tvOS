import SwiftUI

struct SkipSegmentOverlay: View {
    let action: SegmentSkipAction
    let onSkip: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                skipButton
                    .padding(.trailing, SpaceTokens.space3xl)
                    .padding(.bottom, SpaceTokens.space3xl)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: "forward.fill")
                    .font(.bodyLg)
                Text(action.segment.type.skipLabel)
                    .font(.bodyLg)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, SpaceTokens.spaceLg)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(theme.accent.opacity(0.85))
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
}
