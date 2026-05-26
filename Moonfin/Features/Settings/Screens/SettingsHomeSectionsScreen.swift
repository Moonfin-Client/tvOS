import SwiftUI

struct SettingsHomeSectionsScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }

    @State private var sections: [HomeSectionEntry] = []

    var body: some View {
        SettingsScreenLayout(title: "Home Sections") {
            Divider()
                .background(theme.colorScheme.listCaption.opacity(0.3))
                .padding(.vertical, SpaceTokens.spaceXs)

            Text("Row Configuration")
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.bottom, SpaceTokens.space2xs)

            Text("Use select to toggle a row and left/right to reorder")
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
                FocusAwareActionLabel(icon: "arrow.counterclockwise", text: "Reset To Defaults")
            }
            .buttonStyle(CleanButtonStyle())
            .padding(.top, SpaceTokens.spaceMd)
        }
        .onAppear {
            loadSections()
            container.homeScreenSectionsService.requestRefresh()
            container.homePluginSectionsService.requestRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)) { _ in
            loadSections()
        }
        .onReceive(container.pluginSyncService.$syncCompletedCount) { _ in
            loadSections()
        }
        .onReceive(container.homeScreenSectionsService.$refreshCompletedCount.dropFirst()) { _ in
            loadSections()
        }
        .onReceive(container.homePluginSectionsService.$refreshCompletedCount.dropFirst()) { _ in
            loadSections()
        }
    }

    private func loadSections() {
        let sortedConfigs = prefs.homeSectionsConfig.sorted { $0.order < $1.order }
        var seen = Set<HomeSectionType>()
        var seenPluginStableIds = Set<String>()
        var result: [HomeSectionEntry] = []

        for config in sortedConfigs {
            if config.isBuiltin {
                guard config.type != .none, config.type != .mediaBar else { continue }
                guard isVisibleBuiltinTypeInHomeSectionsList(config.type) else { continue }
                guard seen.insert(config.type).inserted else { continue }
                result.append(.builtin(type: config.type, enabled: config.enabled))
                continue
            }

            guard config.isPluginDynamic else { continue }
            guard isVisibleInHomeSectionsList(config) else { continue }
            guard seenPluginStableIds.insert(config.stableId).inserted else { continue }

            let section = (config.pluginSection ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let displayText = (config.pluginDisplayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = !displayText.isEmpty ? displayText : (!section.isEmpty ? section : "Dynamic Row")

            result.append(.plugin(
                config: config,
                title: title,
                subtitle: pluginSubtitle(for: config)
            ))
        }

        for type in HomeSectionType.allCases where type != .none && type != .mediaBar {
            guard isVisibleBuiltinTypeInHomeSectionsList(type) else { continue }
            guard !seen.contains(type) else { continue }
            let fallbackEnabled = HomeSectionType.defaults.first(where: { $0.type == type })?.enabled ?? false
            result.append(.builtin(type: type, enabled: fallbackEnabled))
        }

        sections = result
    }

    private func saveSections() {
        let visibleUpdated: [HomeSectionConfig] = sections.enumerated().map { idx, entry in
            entry.asConfig(order: idx)
        }

        let hiddenExisting: [HomeSectionConfig] = prefs.homeSectionsConfig
            .sorted { $0.order < $1.order }
            .filter { !isVisibleInHomeSectionsList($0) }
            .enumerated()
            .map { idx, config in
                var updated = config
                updated.order = visibleUpdated.count + idx
                return updated
            }

        prefs.setHomeSectionsConfig(HomeSectionConfig.normalized(visibleUpdated + hiddenExisting))
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
        let pluginEntries = sections
            .filter { $0.kind == .pluginDynamic }
            .map { entry in
                var updated = entry
                updated.enabled = false
                return updated
            }

        let defaultBuiltinEntries = HomeSectionType.defaults
            .filter { $0.type != .none && $0.type != .mediaBar }
            .filter { isVisibleBuiltinTypeInHomeSectionsList($0.type) }
            .map { HomeSectionEntry.builtin(type: $0.type, enabled: $0.enabled) }

        sections = defaultBuiltinEntries + pluginEntries
        saveSections()
    }

    private func isVisibleInHomeSectionsList(_ config: HomeSectionConfig) -> Bool {
        if config.isBuiltin {
            return isVisibleBuiltinTypeInHomeSectionsList(config.type)
        }

        guard config.isPluginDynamic else { return false }
        switch config.pluginSource {
        case .collections:
            return prefs[UserPreferences.displayCollectionsRows]
        case .genres:
            return prefs[UserPreferences.displayGenresRows]
        case .hss, .kefinTweaks:
            return true
        }
    }

    private func isVisibleBuiltinTypeInHomeSectionsList(_ type: HomeSectionType) -> Bool {
        switch type {
        case .favorites,
            .favoriteMovies,
            .favoriteSeries,
            .favoriteEpisodes,
            .favoritePeople,
            .favoriteArtists,
            .favoriteMusicVideos,
            .favoriteAlbums,
            .favoriteSongs:
            return prefs[UserPreferences.displayFavoritesRows]
        case .collections:
            return false
        case .genres:
            return false
        default:
            return type != .none && type != .mediaBar
        }
    }

    private func pluginSubtitle(for config: HomeSectionConfig) -> String? {
        var parts: [String] = [pluginSourceDisplayName(config.pluginSource)]

        if let serverName = serverDisplayName(for: config.serverId), !serverName.isEmpty {
            parts.append(serverName)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func pluginSourceDisplayName(_ source: HomeSectionPluginSource) -> String {
        switch source {
        case .hss:
            return "Home Screen Sections"
        case .kefinTweaks:
            return "Kefin Tweaks"
        case .collections:
            return "Collections"
        case .genres:
            return "Genres"
        }
    }

    private func serverDisplayName(for serverId: String?) -> String? {
        guard let serverId, !serverId.isEmpty else { return nil }

        if let uuid = UUID(uuidString: serverId),
           let server = container.serverRepository.storedServers.value.first(where: { $0.id == uuid }) {
            return server.name
        }

        if let server = container.serverRepository.storedServers.value.first(where: {
            normalizedServerIdentifier($0.address) == normalizedServerIdentifier(serverId)
        }) {
            return server.name
        }

        return nil
    }

    private func normalizedServerIdentifier(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}

struct HomeSectionEntry: Identifiable {
    let id: String
    let kind: HomeSectionKind
    let type: HomeSectionType
    let title: String
    let subtitle: String?
    let icon: String
    var enabled: Bool
    let serverId: String?
    let pluginSection: String?
    let pluginAdditionalData: String?
    let pluginDisplayText: String?
    let pluginSource: HomeSectionPluginSource

    static func builtin(type: HomeSectionType, enabled: Bool) -> HomeSectionEntry {
        HomeSectionEntry(
            id: type.rawValue,
            kind: .builtin,
            type: type,
            title: type.displayName,
            subtitle: nil,
            icon: type.icon,
            enabled: enabled,
            serverId: nil,
            pluginSection: nil,
            pluginAdditionalData: nil,
            pluginDisplayText: nil,
            pluginSource: .hss
        )
    }

    static func plugin(config: HomeSectionConfig, title: String, subtitle: String?) -> HomeSectionEntry {
        HomeSectionEntry(
            id: config.stableId,
            kind: .pluginDynamic,
            type: .none,
            title: title,
            subtitle: subtitle,
            icon: pluginIcon(for: config.pluginSource),
            enabled: config.enabled,
            serverId: config.serverId,
            pluginSection: config.pluginSection,
            pluginAdditionalData: config.pluginAdditionalData,
            pluginDisplayText: config.pluginDisplayText ?? title,
            pluginSource: config.pluginSource
        )
    }

    func asConfig(order: Int) -> HomeSectionConfig {
        if kind == .builtin {
            return HomeSectionConfig.builtin(type: type, enabled: enabled, order: order)
        }

        return HomeSectionConfig.pluginDynamic(
            enabled: enabled,
            order: order,
            serverId: serverId,
            pluginSection: pluginSection,
            pluginAdditionalData: pluginAdditionalData,
            pluginDisplayText: pluginDisplayText ?? title,
            pluginSource: pluginSource
        )
    }

    private static func pluginIcon(for source: HomeSectionPluginSource) -> String {
        switch source {
        case .hss:
            return "asset:settings-hss"
        case .kefinTweaks:
            return "asset:settings-kf"
        case .collections:
            return "square.stack.3d.up"
        case .genres:
            return "theatermasks"
        }
    }
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
                icon: entry.icon,
                heading: entry.title,
                caption: entry.subtitle
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
