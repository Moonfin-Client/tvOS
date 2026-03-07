import SwiftUI

struct ToolbarClock: View {
    @State private var currentTime = Date()
    @EnvironmentObject var theme: MoonfinTheme

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(timeString)
            .font(.titleXl)
            .fontWeight(.medium)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.9))
            .monospacedDigit()
            .onReceive(timer) { currentTime = $0 }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: currentTime)
    }
}
