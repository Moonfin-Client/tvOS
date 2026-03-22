import SwiftUI

struct PlayerSeekBar: View {
    let progress: Float
    let bufferProgress: Float
    let isFocused: Bool

    @EnvironmentObject private var theme: MoonfinTheme

    private let barHeight: CGFloat = 4
    private let focusedBarHeight: CGFloat = 6
    private let knobDiameter: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = CGFloat(max(0, min(1, progress)))
            let bufferWidth = max(0, CGFloat(max(0, min(1, bufferProgress))) * width)
            let activeBarHeight = isFocused ? focusedBarHeight : barHeight
            let knobRadius = knobDiameter / 2
            let knobTravelWidth = max(0, width - knobDiameter)
            let knobX = knobRadius + clamped * knobTravelWidth
            let progressWidth = isFocused ? knobX : max(0, clamped * width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: activeBarHeight / 2)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: activeBarHeight)

                if bufferWidth > 0 {
                    RoundedRectangle(cornerRadius: activeBarHeight / 2)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: bufferWidth, height: activeBarHeight)
                }

                RoundedRectangle(cornerRadius: activeBarHeight / 2)
                    .fill(theme.colorScheme.rangeControlFill)
                    .frame(width: progressWidth, height: activeBarHeight)

                if isFocused {
                    Circle()
                        .fill(theme.colorScheme.rangeControlKnob)
                        .frame(width: knobDiameter, height: knobDiameter)
                        .offset(x: knobX - knobRadius)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .drawingGroup()
        }
        .frame(height: knobDiameter)
    }
}

extension PlayerSeekBar: Equatable {
    static func == (lhs: PlayerSeekBar, rhs: PlayerSeekBar) -> Bool {
        abs(lhs.progress - rhs.progress) < 0.001
            && abs(lhs.bufferProgress - rhs.bufferProgress) < 0.01
            && lhs.isFocused == rhs.isFocused
    }
}
