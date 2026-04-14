import SwiftUI

final class MoonfinTheme: ObservableObject {
    private static let focusBorderStorageKey = "focus_border_color"

    @Published var colorScheme: MoonfinColorScheme
    @Published var focusBorder: FocusBorderColor {
        didSet {
            guard oldValue != focusBorder else { return }
            UserDefaults.standard.set(focusBorder.rawValue, forKey: Self.focusBorderStorageKey)
        }
    }

    var accent: Color { .colorCyan500 }

    init(colorScheme: MoonfinColorScheme = .default) {
        let stored = UserDefaults.standard.string(forKey: Self.focusBorderStorageKey)
        self.colorScheme = colorScheme
        self.focusBorder = stored.flatMap(FocusBorderColor.init(rawValue:)) ?? .white
    }
}
