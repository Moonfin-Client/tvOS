import SwiftUI
import os

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var bundle: Bundle = .main
    @Published private(set) var locale: Locale = .current
    @Published private(set) var layoutDirection: LayoutDirection = .leftToRight

    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "Localization")
    private var preferences: LocalizationPreferences?

    private init() {}

    func configure(preferences: LocalizationPreferences) {
        self.preferences = preferences
        let saved = preferences[LocalizationPreferences.appLanguage]
        applyLanguage(saved)
    }

    func setLanguage(_ code: String) {
        preferences?[LocalizationPreferences.appLanguage] = code
        applyLanguage(code)
        logger.info("Language changed to: \(code)")
    }

    var currentLanguageCode: String {
        preferences?[LocalizationPreferences.appLanguage] ?? "system"
    }

    private func applyLanguage(_ code: String) {
        if code == "system" || code.isEmpty {
            bundle = .main
            locale = .current
            layoutDirection = Locale.current.isRTL ? .rightToLeft : .leftToRight
        } else if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let localeBundle = Bundle(path: path) {
            bundle = localeBundle
            locale = Locale(identifier: code)
            layoutDirection = SupportedLocale.rtlLocales.contains(code) ? .rightToLeft : .leftToRight
        } else {
            logger.warning("Locale bundle not found for: \(code), falling back to system")
            bundle = .main
            locale = .current
            layoutDirection = Locale.current.isRTL ? .rightToLeft : .leftToRight
        }
    }
}

private extension Locale {
    var isRTL: Bool {
        guard let lang = language.languageCode?.identifier else { return false }
        return Locale.Language(identifier: lang).characterDirection == .rightToLeft
    }
}
