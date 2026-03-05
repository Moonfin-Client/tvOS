import SwiftUI

struct SplashScreen: View {
    var body: some View {
        Image("SplashBackground")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }
}
