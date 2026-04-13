import SwiftUI

struct SettingsHomeScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    @State private var sections: [HomeSectionEntry] = []

    var body: some View {
        SettingsScreenLayout(title: Strings.home) {
            SettingsListButton(
                icon: "rectangle.expand.vertical",
                heading: Strings.settingsPosterSize,
                caption: Strings.settingsHomePosterSizeDescription,
                trailingText: prefs[UserPreferences.homePosterSize].displayName,
                action: { settingsRouter.navigate(to: .homePosterSize) }
            )
            .focused($focusedRoute, equals: .homePosterSize)

            SettingsListButton(
                icon: "photo",
                heading: Strings.settingsImageType,
                caption: Strings.settingsHomeImageTypeDescription,
                action: { settingsRouter.navigate(to: .homeRowsImageType) }
            )
            .focused($focusedRoute, equals: .homeRowsImageType)

            Divider()
                .background(theme.colorScheme.listCaption.opacity(0.3))
                .padding(.vertical, SpaceTokens.spaceXs)

            Text(Strings.settingsSections)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.bottom, SpaceTokens.space2xs)

            Text(Strings.settingsRearrangeHint)
                .font(.caption)
                .foregroundColor(theme.colorScheme.listCaption)
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
                FocusAwareActionLabel(icon: "arrow.counterclockwise", text: Strings.settingsResetToDefaults)
            }
            .buttonStyle(CleanButtonStyle())
            .padding(.top, SpaceTokens.spaceMd)
        }
        .onAppear { loadSections() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)) { _ in
            loadSections()
        }
        .onReceive(container.pluginSyncService.$syncCompletedCount) { _ in
            loadSections()
        }
        .restoresFocus($focusedRoute)
    }

    private func loadSections() {
        let raw = prefs[UserPreferences.homeSections]
        if raw.isEmpty {
            sections = HomeSectionType.defaults.map { entry in
                HomeSectionEntry(type: entry.type, enabled: entry.enabled)
            }
        } else {
            let active = raw.split(separator: ",")
                .compactMap { rawValue -> HomeSectionType? in
                    let value = String(rawValue).trimmingCharacters(in: .whitespaces)
                    return HomeSectionType(rawValue: value) ?? HomeSectionType.from(serverName: value)
                }
            var seenSections = Set<HomeSectionType>()
            let uniqueActive = active.filter { seenSections.insert($0).inserted }
            var result: [HomeSectionEntry] = uniqueActive.map { HomeSectionEntry(type: $0, enabled: true) }
            for def in HomeSectionType.defaults {
                if !uniqueActive.contains(def.type) {
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
        Button(action: onToggle) {
            SettingsItemContent(
                icon: entry.type.icon,
                heading: entry.type.displayName,
                caption: nil
            ) { isFocused in
                HStack(spacing: SpaceTokens.spaceSm) {
                    if !isFirst {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
                    }
                    if !isLast {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
                    }
                    Image(systemName: entry.enabled ? "checkmark.circle.fill" : "circle")
                        .font(.bodyLg)
                        .foregroundColor(entry.enabled
                            ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                            : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
                }
            }
        }
        .buttonStyle(CleanButtonStyle())
        .onMoveCommand { direction in
            switch direction {
            case .left: onMoveUp()
            case .right: onMoveDown()
            default: break
            }
        }
    }
}
