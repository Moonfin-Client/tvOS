import SwiftUI

struct LoginBackground: View {
    private static let gradientStart = Color(hex: 0x0A0A0A)
    private static let gradientMid = Color(hex: 0x1A1A2E)
    private static let gradientEnd = Color(hex: 0x16213E)

    var body: some View {
        LinearGradient(
            colors: [Self.gradientStart, Self.gradientMid, Self.gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
