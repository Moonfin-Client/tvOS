import SwiftUI

struct SettingsAppearanceThemeScreen: View {
    @EnvironmentObject private var theme: MoonfinTheme
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settingsRouter: SettingsRouter

    @FocusState private var focusedThemeId: String?

    private var sortedThemes: [ThemeSpec] {
        ThemeRegistry.shared.availableThemes.values.sorted { lhs, rhs in
            let leftRank = sortRank(lhs.id)
            let rightRank = sortRank(rhs.id)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        SettingsScreenLayout(title: "Appearance Theme") {
            ForEach(sortedThemes, id: \.id) { spec in
                Button {
                    theme.applyThemeById(container.userPreferences, themeId: spec.id)
                } label: {
                    AppearanceThemeRow(
                        title: title(for: spec),
                        subtitle: subtitle(for: spec),
                        selected: selectedThemeId == spec.id,
                        colorPreview: [
                            spec.colors.background.color,
                            spec.colors.surface.color,
                            spec.colors.accent.color,
                            spec.colors.rangeProgress.color
                        ]
                    )
                }
                .buttonStyle(CleanButtonStyle())
                .focused($focusedThemeId, equals: spec.id)
            }
        }
    }

    private var selectedThemeId: String {
        if !theme.activeCustomId.isEmpty {
            return theme.activeCustomId
        }
        return MoonfinTheme.builtInThemeIdFor(theme.activeThemeId)
    }

    private func sortRank(_ id: String) -> Int {
        if id == ThemeRegistry.moonfinId { return 0 }
        if id == ThemeRegistry.neonPulseId { return 1 }
        return 2
    }

    private func title(for spec: ThemeSpec) -> String {
        switch spec.id {
        case ThemeRegistry.moonfinId:
            return "Moonfin"
        case ThemeRegistry.neonPulseId:
            return "Neon Pulse"
        default:
            return spec.displayName
        }
    }

    private func subtitle(for spec: ThemeSpec) -> String {
        switch spec.id {
        case ThemeRegistry.moonfinId:
            return "Default Moonfin appearance"
        case ThemeRegistry.neonPulseId:
            return "High-contrast neon style"
        default:
            return "Custom theme from plugin"
        }
    }
}

private struct AppearanceThemeRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let colorPreview: [Color]

    @EnvironmentObject private var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                Text(title)
                    .font(.bodyMd)
                    .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)

                Text(subtitle)
                    .font(.captionXs)
                    .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)

                HStack(spacing: 4) {
                    ForEach(Array(colorPreview.enumerated()), id: \.offset) { entry in
                        RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                            .fill(entry.element)
                            .frame(width: 24, height: 12)
                    }
                }
            }

            Spacer()

            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.bodyMd)
                .foregroundColor(selected
                    ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                    : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                .fill(isFocused ? theme.colorScheme.listButtonFocused : theme.colorScheme.listButton)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
