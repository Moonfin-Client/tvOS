import SwiftUI

struct SettingsHomeScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

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
            .focused($focusedRoute, equals: .homePosterSize)

            SettingsListButton(
                icon: "photo",
                heading: "Image Type",
                caption: "Type of image shown on cards",
                trailingText: prefs[UserPreferences.homeRowsImageType].displayName,
                action: { settingsRouter.navigate(to: .homeRowsImageType) }
            )
            .focused($focusedRoute, equals: .homeRowsImageType)

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
        HStack(spacing: SpaceTokens.spaceSm) {
            SectionArrowButton(icon: "chevron.up", disabled: isFirst, action: onMoveUp)
            SectionArrowButton(icon: "chevron.down", disabled: isLast, action: onMoveDown)

            Button(action: onToggle) {
                SectionToggleContent(entry: entry)
            }
            .buttonStyle(CleanButtonStyle())
        }
        .padding(.vertical, SpaceTokens.space2xs)
    }
}

private struct SectionArrowButton: View {
    let icon: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SectionArrowContent(icon: icon, disabled: disabled)
        }
        .buttonStyle(CleanButtonStyle())
        .disabled(disabled)
    }
}

private struct SectionArrowContent: View {
    let icon: String
    let disabled: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(disabled
                ? theme.colorScheme.listCaption.opacity(0.3)
                : (isFocused ? .black : theme.accent))
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused && !disabled ? Color.white : Color.clear)
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

private struct SectionToggleContent: View {
    let entry: HomeSectionEntry

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            Image(systemName: entry.type.icon)
                .font(.bodyLg)
                .foregroundColor(entry.enabled
                    ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                    : theme.colorScheme.listCaption)
                .frame(width: 28)

            Text(entry.type.displayName)
                .font(.bodyMd)
                .foregroundColor(entry.enabled
                    ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)
                    : theme.colorScheme.listCaption)

            Spacer()

            Image(systemName: entry.enabled ? "checkmark.circle.fill" : "circle")
                .font(.bodyLg)
                .foregroundColor(entry.enabled
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
