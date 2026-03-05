import SwiftUI

struct PersonAvatarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 640, rect.height / 621)
        let ox = rect.midX - 480 * s
        let oy = rect.midY - 489.5 * s

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * s + ox, y: y * s + oy)
        }

        var path = Path()

        path.move(to: p(372, 437))
        path.addQuadCurve(to: p(330, 329), control: p(330, 395))
        path.addQuadCurve(to: p(372, 221), control: p(330, 263))
        path.addQuadCurve(to: p(480, 179), control: p(414, 179))
        path.addQuadCurve(to: p(588, 221), control: p(546, 179))
        path.addQuadCurve(to: p(630, 329), control: p(630, 263))
        path.addQuadCurve(to: p(588, 437), control: p(630, 395))
        path.addQuadCurve(to: p(480, 479), control: p(546, 479))
        path.addQuadCurve(to: p(372, 437), control: p(414, 479))
        path.closeSubpath()

        path.move(to: p(160, 800))
        path.addLine(to: p(160, 706))
        path.addQuadCurve(to: p(179, 641), control: p(160, 668))
        path.addQuadCurve(to: p(228, 600), control: p(198, 614))
        path.addQuadCurve(to: p(356.5, 555), control: p(295, 570))
        path.addQuadCurve(to: p(480, 540), control: p(418, 540))
        path.addQuadCurve(to: p(603, 555.5), control: p(542, 540))
        path.addQuadCurve(to: p(731, 600), control: p(664, 571))
        path.addQuadCurve(to: p(781, 641), control: p(762, 614))
        path.addQuadCurve(to: p(800, 706), control: p(800, 668))
        path.addLine(to: p(800, 800))
        path.addLine(to: p(160, 800))
        path.closeSubpath()

        return path
    }
}
