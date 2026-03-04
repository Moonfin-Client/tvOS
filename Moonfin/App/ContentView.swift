import SwiftUI

struct ContentView: View {
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()
            VStack(spacing: SpaceTokens.spaceLg) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(theme.accent)
                Text("Moonfin")
                    .font(.title3xl)
                    .foregroundColor(theme.colorScheme.onBackground)
            }
        }
    }
}

#Preview {
    ContentView()
}
