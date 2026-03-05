import SwiftUI

struct JellyfinLogo: View {
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        JellyfinLogoShape()
            .fill(color, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    }
}

struct JellyfinLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 512.0
        let ox = rect.minX
        let oy = rect.minY

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * s + ox, y: y * s + oy)
        }

        var path = Path()

        path.move(to: p(256, 0))
        path.addCurve(
            to: p(3.4, 462.2),
            control1: p(188.3, 0),
            control2: p(-29.8, 395.4)
        )
        path.addCurve(
            to: p(508.6, 462.2),
            control1: p(36.6, 529.0),
            control2: p(475.7, 528.2)
        )
        path.addCurve(
            to: p(256, 0),
            control1: p(541.5, 396.2),
            control2: p(323.8, 0)
        )
        path.closeSubpath()

        path.move(to: p(421.6, 404.3))
        path.addCurve(
            to: p(90.5, 404.3),
            control1: p(400.0, 447.5),
            control2: p(112.3, 448.1)
        )
        path.addCurve(
            to: p(256, 101.4),
            control1: p(68.7, 360.5),
            control2: p(211.7, 101.4)
        )
        path.addCurve(
            to: p(421.6, 404.3),
            control1: p(300.3, 101.4),
            control2: p(443.2, 361)
        )
        path.closeSubpath()

        path.move(to: p(256, 196.2))
        path.addCurve(
            to: p(172.2, 349.6),
            control1: p(233.6, 196.2),
            control2: p(161.2, 327.5)
        )
        path.addCurve(
            to: p(339.9, 349.6),
            control1: p(183.2, 371.7),
            control2: p(329.0, 371.5)
        )
        path.addCurve(
            to: p(256, 196.2),
            control1: p(350.8, 327.7),
            control2: p(278.6, 196.2)
        )
        path.closeSubpath()

        return path
    }
}
