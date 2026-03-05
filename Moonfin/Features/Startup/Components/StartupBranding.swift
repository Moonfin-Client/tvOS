import SwiftUI

struct StartupBranding: View {
    var body: some View {
        Image("LogoText")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 360)
    }
}
