import SwiftUI

final class MoonfinTheme: ObservableObject {
    @Published var colorScheme: MoonfinColorScheme
    @Published var focusBorder: FocusBorderColor

    var accent: Color { .colorCyan500 }

    init(
        colorScheme: MoonfinColorScheme = .default,
        focusBorder: FocusBorderColor = .white
    ) {
        self.colorScheme = colorScheme
        self.focusBorder = focusBorder
    }
}
