import SwiftUI

struct SettingsHomeScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }

    @State private var sections: [HomeSectionEntry] = []

    var body: some View {
        SettingsScreenLayout(title: "Home") {
            SettingsListButton(
                icon: "rectangle.expand.vertical",
                heading: "Poster Size",
                caption: "Size of cards on the home screen",
                trailingText: prefs[UserPreferences.homePosterSize].displayName,
                action: { settingsRouter.navigate(to: .homePosterSize) }
            )

            SettingsListButton(
                icon: "photo",
                heading: "Image Type",
                caption: "Type of image shown on cards",
                trailingText: prefs[UserPreferences.homeRowsImageType].displayName,
                action: { settingsRouter.navigate(to: .homeRowsImageType) }
            )

            Divider()
                .background(theme.colorScheme.listCaption.opacity(0.3))
                .padding(.vertical, SpaceTokens.spaceXs)

            Text("Sections")
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.bottom, SpaceTokens.space2xs)

            ForEach(Array(sections.enumerated()), id: \.element.id) { index, entry in
                HomeSectionRow(
                    entry: entry,
                    isFirst: index == 0,
                    isLast: index == sections.count - 1,
                    onToggle: { toggleSection(at: index) },
                    onMoveUp: { moveSection(from: index, direction: -1) },
                    onMoveDown: { moveSection(from: index, direction: 1) }
                )
            }

            Button(action: resetToDefaults) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Defaults")
                }
                .font(.bodyMd)
                .foregroundColor(theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, SpaceTokens.spaceMd)
            }
            .buttonStyle(CleanButtonStyle())
        }
        .onAppear { loadSections() }
    }

    private func loadSections() {
        let raw = prefs[UserPreferences.homeSections]
        if raw.isEmpty {
            sections = HomeSectionType.defaults.map { entry in
                HomeSectionEntry(type: entry.type, enabled: entry.enabled)
            }
        } else {
            let active = raw.split(separator: ",")
                .compactMap { HomeSectionType(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
            var result: [HomeSectionEntry] = active.map { HomeSectionEntry(type: $0, enabled: true) }
            for def in HomeSectionType.defaults {
                if !active.contains(def.type) {
                    result.append(HomeSectionEntry(type: def.type, enabled: false))
                }
            }
            sections = result
        }
    }

    private func saveSections() {
        let enabled = sections.filter(\.enabled).map(\.type.rawValue)
        prefs[UserPreferences.homeSections] = enabled.joined(separator: ",")
    }

    private func toggleSection(at index: Int) {
        sections[index].enabled.toggle()
        saveSections()
    }

    private func moveSection(from index: Int, direction: Int) {
        let target = index + direction
        guard target >= 0 && target < sections.count else { return }
        sections.swapAt(index, target)
        saveSections()
    }

    private func resetToDefaults() {
        sections = HomeSectionType.defaults.map { entry in
            HomeSectionEntry(type: entry.type, enabled: entry.enabled)
        }
        prefs[UserPreferences.homeSections] = ""
    }
}

struct HomeSectionEntry: Identifiable {
    var id: String { type.rawValue }
    let type: HomeSectionType
    var enabled: Bool
}

private struct HomeSectionRow: View {
    let entry: HomeSectionEntry
    let isFirst: Bool
    let isLast: Bool
    let onToggle: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isFirst ? theme.colorScheme.listCaption.opacity(0.3) : theme.accent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(CleanButtonStyle())
            .disabled(isFirst)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isLast ? theme.colorScheme.listCaption.opacity(0.3) : theme.accent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(CleanButtonStyle())
            .disabled(isLast)

            Image(systemName: entry.type.icon)
                .font(.system(size: 16))
                .foregroundColor(entry.enabled ? theme.accent : theme.colorScheme.listCaption)
                .frame(width: 24)

            Text(entry.type.displayName)
                .font(.bodyMd)
                .foregroundColor(entry.enabled ? theme.colorScheme.onBackground : theme.colorScheme.listCaption)

            Spacer()

            Button(action: onToggle) {
                Image(systemName: entry.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(entry.enabled ? theme.accent : theme.colorScheme.listCaption)
            }
            .buttonStyle(CleanButtonStyle())
        }
        .padding(.vertical, SpaceTokens.space2xs)
    }
}
