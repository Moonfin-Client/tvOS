import SwiftUI

struct SettingsLanguageScreen: View {
    @EnvironmentObject var localization: LocalizationManager
    @FocusState private var focusedLanguageCode: String?
    @State private var selectedCode = "system"

    private var languageOptions: [SupportedLocale] {
        [.system] + SupportedLocale.allCases.filter { $0 != .system }
    }

    var body: some View {
        SettingsScreenLayout(title: "Language") {
            ForEach(languageOptions) { locale in
                languageButton(for: locale)
                    .focused($focusedLanguageCode, equals: locale.rawValue)
            }
        }
        .defaultFocus($focusedLanguageCode, "system")
        .onAppear {
            selectedCode = localization.currentLanguageCode
            if focusedLanguageCode == nil {
                focusedLanguageCode = selectedCode
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            selectedCode = localization.currentLanguageCode
        }
    }

    private func languageButton(for locale: SupportedLocale) -> some View {
        let isSelected = selectedCode == locale.rawValue
        return Button {
            selectedCode = locale.rawValue
            localization.setLanguage(locale.rawValue)
        } label: {
            SettingsItemContent(
                icon: isSelected ? "checkmark.circle.fill" : "circle",
                heading: locale.displayName,
                caption: locale != .system && !locale.nativeName.isEmpty && locale.nativeName != locale.displayName
                    ? locale.nativeName
                    : nil
            ) { _ in
                EmptyView()
            }
        }
        .buttonStyle(CleanButtonStyle())
    }
}
