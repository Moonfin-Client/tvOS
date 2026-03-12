import SwiftUI

struct SettingsLanguageScreen: View {
    @EnvironmentObject var localization: LocalizationManager

    private var selectedCode: String {
        localization.currentLanguageCode
    }

    var body: some View {
        SettingsScreenLayout(title: "Language") {
            languageButton(for: .system)

            ForEach(SupportedLocale.allCases.filter { $0 != .system }) { locale in
                languageButton(for: locale)
            }
        }
    }

    private func languageButton(for locale: SupportedLocale) -> some View {
        let isSelected = selectedCode == locale.rawValue
        return Button {
            localization.setLanguage(locale.rawValue)
        } label: {
            HStack(spacing: SpaceTokens.spaceMd) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: SpaceTokens.spaceSm / 2) {
                    Text(locale.displayName)
                        .font(.bodyMd)
                    if locale != .system, !locale.nativeName.isEmpty, locale.nativeName != locale.displayName {
                        Text(locale.nativeName)
                            .font(.bodySm)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceSm)
        }
        .buttonStyle(CleanButtonStyle())
    }
}
