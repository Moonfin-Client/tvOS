import SwiftUI

struct MoonfinLogo: View {
    var size: CGFloat = 32

    var body: some View {
        MoonfinLogoShape()
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0xAA5CC3), Color(hex: 0x00A4DC)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
    }
}

struct MoonfinLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let svgMinX: CGFloat = 195
        let svgMinY: CGFloat = 330
        let svgSpan: CGFloat = 140
        let scale = min(rect.width, rect.height) / svgSpan
        let offsetX = rect.midX - (svgMinX + svgSpan / 2) * scale
        let offsetY = rect.midY - (svgMinY + svgSpan / 2) * scale

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
        }

        path.move(to: p(278.379, 334.184))
        path.addCurve(to: p(271.204, 336.094),
                       control1: p(278.431, 334.499),
                       control2: p(277.993, 334.490))
        path.addCurve(to: p(231.802, 397.073),
                       control1: p(244.532, 343.869),
                       control2: p(226.935, 369.051))
        path.addCurve(to: p(260.808, 418.333),
                       control1: p(234.523, 412.740),
                       control2: p(243.857, 423.179))
        path.addCurve(to: p(309.838, 367.159),
                       control1: p(280.111, 412.814),
                       control2: p(282.582, 396.201))
        path.addCurve(to: p(319.814, 360.681),
                       control1: p(314.283, 361.366),
                       control2: p(319.654, 353.769))
        path.addCurve(to: p(330.061, 407.618),
                       control1: p(318.725, 364.815),
                       control2: p(317.049, 368.768))
        path.addLine(to: p(327.868, 416.376))
        path.addCurve(to: p(294.760, 414.253),
                       control1: p(324.266, 414.708),
                       control2: p(320.515, 412.922))
        path.addCurve(to: p(244.000, 433.788),
                       control1: p(287.812, 413.254),
                       control2: p(279.707, 416.062))
        path.addCurve(to: p(200.414, 419.555),
                       control1: p(229.710, 436.892),
                       control2: p(206.439, 435.532))
        path.addCurve(to: p(208.034, 359.717),
                       control1: p(193.219, 400.476),
                       control2: p(196.663, 376.436))
        path.addCurve(to: p(278.379, 334.184),
                       control1: p(223.437, 338.314),
                       control2: p(251.652, 327.803))
        path.closeSubpath()

        path.move(to: p(325.683, 423.752))
        path.addCurve(to: p(306.293, 436.005),
                       control1: p(323.760, 428.711),
                       control2: p(321.234, 433.170))
        path.addCurve(to: p(247.123, 455.507),
                       control1: p(284.115, 437.214),
                       control2: p(266.043, 456.996))
        path.addLine(to: p(250.366, 456.531))
        path.addCurve(to: p(309.647, 445.652),
                       control1: p(271.137, 462.795),
                       control2: p(290.051, 446.611))
        path.addCurve(to: p(315.225, 446.197),
                       control1: p(310.319, 445.619),
                       control2: p(315.228, 445.564))
        path.addCurve(to: p(276.889, 465.072),
                       control1: p(305.979, 455.564),
                       control2: p(293.837, 462.366))
        path.addCurve(to: p(208.524, 437.434),
                       control1: p(250.445, 470.597),
                       control2: p(223.814, 459.246))
        path.addLine(to: p(208.630, 437.110))
        path.addCurve(to: p(228.185, 445.586),
                       control1: p(214.167, 441.433),
                       control2: p(221.239, 444.431))
        path.addCurve(to: p(300.239, 423.162),
                       control1: p(257.610, 450.479),
                       control2: p(274.025, 428.013))
        path.addCurve(to: p(325.683, 423.752),
                       control1: p(308.839, 421.392),
                       control2: p(317.216, 421.222))
        path.closeSubpath()

        return path
    }
}
