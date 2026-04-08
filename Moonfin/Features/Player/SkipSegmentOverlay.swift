import SwiftUI

struct SkipSegmentOverlay: View {
    let action: SegmentSkipAction

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                skipPill
                    .padding(.trailing, SpaceTokens.space3xl)
                    .padding(.bottom, 260)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var skipPill: some View {
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
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.medium)
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
        )
        .foregroundColor(.white)
    }
}
