import SwiftUI

struct PlayerSeekBar: View {
    let progress: Float
    let bufferProgress: Float
    let isFocused: Bool

    @EnvironmentObject private var theme: MoonfinTheme

    private let barHeight: CGFloat = 6
    private let knobSize: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progressWidth = CGFloat(progress) * width
            let bufferWidth = CGFloat(bufferProgress) * width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(theme.colorScheme.rangeControlBackground)
                    .frame(height: barHeight)

                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(theme.colorScheme.seekbarBuffer)
                    .frame(width: bufferWidth, height: barHeight)

                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(theme.colorScheme.rangeControlFill)
                    .frame(width: progressWidth, height: barHeight)

                if isFocused {
                    Circle()
                        .fill(theme.colorScheme.rangeControlKnob)
                        .frame(width: knobSize, height: knobSize)
                        .offset(x: progressWidth - knobSize / 2)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: knobSize)
    }
}
