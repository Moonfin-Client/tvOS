import SwiftUI

struct PlayerSeekBar: View {
    let progress: Float
    let bufferProgress: Float
    let isFocused: Bool

    @EnvironmentObject private var theme: MoonfinTheme

    private let barHeight: CGFloat = 4
    private let knobDiameter: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = CGFloat(max(0, min(1, progress)))
            let progressWidth = clamped * width
            let bufferWidth = CGFloat(max(0, min(1, bufferProgress))) * width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: barHeight)

                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: bufferWidth, height: barHeight)

                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(theme.colorScheme.rangeControlFill)
                    .frame(width: progressWidth, height: barHeight)

                Circle()
                    .fill(theme.colorScheme.rangeControlKnob)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .offset(x: progressWidth - knobDiameter / 2)
                    .opacity(isFocused ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: knobDiameter)
    }
}
