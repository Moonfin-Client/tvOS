import SwiftUI

struct EmbyLogo: View {
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        EmbyLogoShape()
            .fill(color, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    }
}

struct EmbyLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 512.0
        let ox = rect.minX
        let oy = rect.minY

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * s + ox, y: y * s + oy)
        }

        var path = Path()

        path.move(to: p(97.1, 132.4))
        path.addLine(to: p(123.6, 158.9))
        path.addLine(to: p(0, 282.5))
        path.addLine(to: p(132.4, 414.9))
        path.addLine(to: p(158.9, 388.4))
        path.addLine(to: p(282.5, 512))
        path.addLine(to: p(423.7, 370.8))
        path.addLine(to: p(397.2, 344.3))
        path.addLine(to: p(512, 229.5))
        path.addLine(to: p(379.6, 97.1))
        path.addLine(to: p(353.1, 123.6))
        path.addLine(to: p(229.5, 0))
        path.closeSubpath()

        path.move(to: p(196.8, 351.2))
        path.addLine(to: p(196.8, 158.2))
        path.addLine(to: p(366, 254.7))
        path.addLine(to: p(281.4, 303))
        path.closeSubpath()

        return path
    }
}
