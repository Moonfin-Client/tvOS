import Foundation
import Combine

@MainActor
final class PluginSyncService: ObservableObject {
    @Published private(set) var isPluginAvailable = false
    @Published private(set) var syncCompletedCount = 0

    private let resolveClient: () -> HttpClient?
    private let resolveSeerrRepository: () -> SeerrRepositoryProtocol?
    private let resolveParentalRepository: () -> ParentalControlsRepository?
    private let defaults: UserDefaults

    private var serverSchemaVersion = 1
    private var pendingSeerrRowsConfig: [String: Any]?
    private var pushTask: Task<Void, Never>?
    private var sseTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?
    private var seerrChangeObserver: NSObjectProtocol?
    private var parentalChangeObserver: NSObjectProtocol?

    init(
        resolveClient: @escaping () -> HttpClient?,
        resolveSeerrRepository: @escaping () -> SeerrRepositoryProtocol? = { nil },
        resolveParentalRepository: @escaping () -> ParentalControlsRepository? = { nil },
        defaults: UserDefaults = .standard
    ) {
        self.resolveClient = resolveClient
        self.resolveSeerrRepository = resolveSeerrRepository
        self.resolveParentalRepository = resolveParentalRepository
        self.defaults = defaults
    }

    func syncOnStartup() async {
        let syncEnabled = defaults.bool(forKey: UserPreferences.pluginSyncEnabled.key)

        if !syncEnabled {
            sseTask?.cancel()
            sseTask = nil
            unregisterChangeListener()
            return
        }

        guard let client = resolveClient(), client.isUsable else {
            sseTask?.cancel()
            sseTask = nil
            return
        }

        let available = await ping(client: client)
        isPluginAvailable = available

        guard available else {
            sseTask?.cancel()
            sseTask = nil
            return
        }

        await refreshCustomThemes(client: client)

        let serverSettings = await fetchServerSettings(client: client)
        let localSettings = collectLocalSettings()
        let snapshot = loadSnapshot()

        if let serverSettings {
            let merged = mergeThreeWay(local: localSettings, server: serverSettings, snapshot: snapshot)
            applySettings(merged)
            applySeerrRowConfig()
            await pushSettings(client: client, settings: merged)
            saveSnapshot(merged)
            syncCompletedCount += 1
        } else {
            await pushSettings(client: client, settings: localSettings)
            saveSnapshot(localSettings)
        }

        registerChangeListener()
        await configureJellyseerrProxy(client: client)
        startSseListener(client: client)
    }

    func initialSync() async {
        sseTask?.cancel()
        sseTask = nil
        clearSnapshot()
        await syncOnStartup()
    }

    private func pullAndApplySettings(client: HttpClient) async {
        guard let serverSettings = await fetchServerSettings(client: client) else { return }

        applySettings(serverSettings)
        applySeerrRowConfig()
        syncCompletedCount += 1
    }

    private func startSseListener(client: HttpClient) {
        sseTask?.cancel()

        sseTask = Task { [weak self] in
            guard let self else { return }

            var reconnectAttempt: UInt64 = 0

            while !Task.isCancelled {
                guard let baseURL = client.baseURL else { return }

                var didReceiveAnyLine = false

                do {
                    let streamPath = "\(PluginSyncConstants.settingsPath)/Stream"
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

                    var request = URLRequest(url: baseURL.appendingPathComponent(streamPath))
                    request.httpMethod = "GET"
                    request.setValue(client.authorizationHeader, forHTTPHeaderField: "Authorization")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }

                    for try await rawLine in bytes.lines {
                        try Task.checkCancellation()

                        didReceiveAnyLine = true

                        if !rawLine.hasPrefix("data:") {
                            continue
                        }

                        let payload = rawLine.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if payload.isEmpty {
                            continue
                        }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String,
                              type == "settingsUpdated" else {
                            continue
                        }

                        await self.pullAndApplySettings(client: client)
                    }
                } catch {
                    if Task.isCancelled {
                        break
                    }
                }

                if Task.isCancelled {
                    break
                }

                if didReceiveAnyLine {
                    reconnectAttempt = 0
                }

                let delaySeconds = min(UInt64(1) << reconnectAttempt, UInt64(30))
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)

                if !didReceiveAnyLine {
                    reconnectAttempt = min(reconnectAttempt + 1, 6)
                }
            }
        }
    }

    // MARK: - Ping

    private func ping(client: HttpClient) async -> Bool {
        do {
            try await client.requestVoid(PluginSyncConstants.pingPath, method: "GET")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Fetch

    private func fetchServerSettings(client: HttpClient) async -> [String: Any]? {
        guard let baseURL = client.baseURL else { return nil }

        let components = URLComponents(url: baseURL.appendingPathComponent(PluginSyncConstants.settingsPath), resolvingAgainstBaseURL: false)
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(client.authorizationHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let schemaVersion = (json["SchemaVersion"] as? Int) ?? (json["schemaVersion"] as? Int) ?? 1
            serverSchemaVersion = schemaVersion

            if schemaVersion >= 2 {
                let selectedProfile = selectedCustomizationProfile()
                let globalProfile = profileJson(for: .global, in: json)
                let targetProfile = profileJson(for: selectedProfile, in: json)
                return resolveV2Profile(global: globalProfile, profile: targetProfile)
            } else {
                return json.reduce(into: [String: Any]()) { result, pair in
                    result[toCamelCase(pair.key)] = pair.value
                }
            }
        } catch {
            return nil
        }
    }

    private func resolveV2Profile(global: [String: Any]?, profile: [String: Any]?) -> [String: Any] {
        var resolved = [String: Any]()

        if let global {
            for (key, value) in global {
                let camelKey = toCamelCase(key)
                if PluginSyncConstants.allServerKeys.contains(camelKey) {
                    resolved[camelKey] = value
                }
            }
        }

        if let profile {
            for (key, value) in profile {
                if value is NSNull { continue }
                let camelKey = toCamelCase(key)
                if PluginSyncConstants.allServerKeys.contains(camelKey) {
                    if camelKey == "homeRowOrder", let tvRows = value as? [Any] {
                        // Skip if written by old Apple TV code using Swift rawValues ("nextUp") instead of server names ("nextup").
                        let hasCamelCase = tvRows.contains { ($0 as? String)?.contains(where: \.isUppercase) ?? false }
                        if hasCamelCase { continue }
                    }
                    resolved[camelKey] = value
                }
            }
        }

        pendingSeerrRowsConfig = (profile?["jellyseerrRows"] ?? profile?["JellyseerrRows"]
            ?? global?["jellyseerrRows"] ?? global?["JellyseerrRows"]) as? [String: Any]

        return resolved
    }

    private func selectedCustomizationProfile() -> PluginCustomizationProfile {
        let raw = defaults.string(forKey: UserPreferences.pluginCustomizationProfile.key) ?? PluginCustomizationProfile.tv.rawValue
        return PluginCustomizationProfile(rawValue: raw) ?? .tv
    }

    private func profileJson(for profile: PluginCustomizationProfile, in json: [String: Any]) -> [String: Any]? {
        let keys: [String]
        switch profile {
        case .global:
            keys = ["Global", "global"]
        case .desktop:
            keys = ["Desktop", "desktop"]
        case .mobile:
            keys = ["Mobile", "mobile"]
        case .tv:
            keys = ["Tv", "TV", "tv"]
        }

        for key in keys {
            if let map = json[key] as? [String: Any] {
                return map
            }
        }
        return nil
    }

    // MARK: - Push

    private func pushSettings(client: HttpClient, settings: [String: Any]) async {
        guard let baseURL = client.baseURL else { return }

        let path: String
        let bodyDict: [String: Any]

        if serverSchemaVersion >= 2 {
            let profilePath = selectedCustomizationProfile().rawValue
            path = "\(PluginSyncConstants.settingsPath)/Profile/\(profilePath)"
            bodyDict = [
                "profile": settings,
                "clientId": PluginSyncConstants.clientId
            ]
        } else {
            path = PluginSyncConstants.settingsPath
            bodyDict = [
                "settings": settings,
                "clientId": PluginSyncConstants.clientId
            ]
        }

        let components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.authorizationHeader, forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
            _ = try await URLSession.shared.data(for: request)
        } catch { }
    }

    // MARK: - Collect local

    private func collectLocalSettings() -> [String: Any] {
        var map = [String: Any]()
        for sp in PluginSyncConstants.syncablePreferences {
            map[sp.serverKey] = readLocalValue(sp)
        }
        if let seerrRows = collectSeerrRowsConfig() {
            map["jellyseerrRows"] = seerrRows
        }
        return map
    }

    private func readLocalValue(_ sp: SyncablePreference) -> Any {
        let store = defaultsForPreference(sp)
        guard store.object(forKey: sp.key) != nil else { return sp.defaultValue }

        switch sp.type {
        case .boolean:
            return store.bool(forKey: sp.key)
        case .int:
            return store.integer(forKey: sp.key)
        case .string, .enum:
            return store.string(forKey: sp.key) ?? sp.defaultValue
        case .list:
            return readListValue(sp, store: store)
        }
    }

    // MARK: - Apply

    private func applySettings(_ settings: [String: Any]) {
        var pendingMediaBarMode: Any?
        var hasLegacyMediaBarEnabled = false

        for (serverKey, value) in settings {
            guard let sp = PluginSyncConstants.serverToLocal[serverKey] else { continue }

            if sp.key == UserPreferences.mediaBarMode.key {
                pendingMediaBarMode = value
                continue
            }

            if sp.key == UserPreferences.mediaBarEnabled.key {
                hasLegacyMediaBarEnabled = true
            }

            writeLocalValue(sp, value: value)
        }

        if let pendingMediaBarMode {
            writeMediaBarMode(pendingMediaBarMode, store: defaults)
        } else if hasLegacyMediaBarEnabled {
            let enabled = defaults.bool(forKey: UserPreferences.mediaBarEnabled.key)
            defaults.set(enabled ? MediaBarMode.moonfin.rawValue : MediaBarMode.off.rawValue, forKey: UserPreferences.mediaBarMode.key)
        }

        resolveParentalRepository()?.reloadBlockedRatings()
    }

    private func writeLocalValue(_ sp: SyncablePreference, value: Any) {
        let store = defaultsForPreference(sp)
        switch sp.type {
        case .boolean:
            if let b = value as? Bool {
                store.set(b, forKey: sp.key)
            } else if let s = value as? String, let b = Bool(s) {
                store.set(b, forKey: sp.key)
            } else if let n = value as? NSNumber {
                store.set(n.boolValue, forKey: sp.key)
            }
        case .int:
            if let i = value as? Int {
                store.set(i, forKey: sp.key)
            } else if let n = value as? NSNumber {
                store.set(n.intValue, forKey: sp.key)
            } else if let s = value as? String, let i = Int(s) {
                store.set(i, forKey: sp.key)
            }
        case .string, .enum:
            if sp.key == UserPreferences.visualTheme.key {
                store.set(normalizedVisualThemeString(value), forKey: sp.key)
            } else if sp.key == UserPreferences.mediaBarMode.key {
                writeMediaBarMode(value, store: store)
            } else {
                store.set("\(value)", forKey: sp.key)
            }
        case .list:
            writeListValue(sp, value: value, store: store)
        }
    }

    private func normalizedMediaBarMode(_ value: Any) -> MediaBarMode? {
        let normalized = "\(value)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case MediaBarMode.moonfin.rawValue:
            return .moonfin
        case MediaBarMode.makd.rawValue:
            return .makd
        case MediaBarMode.off.rawValue:
            return .off
        case "true", "1", "enabled", "on":
            return .moonfin
        case "false", "0", "disabled":
            return .off
        default:
            return nil
        }
    }

    private func writeMediaBarMode(_ value: Any, store: UserDefaults) {
        guard let mode = normalizedMediaBarMode(value) else { return }
        store.set(mode.rawValue, forKey: UserPreferences.mediaBarMode.key)
        store.set(mode != .off, forKey: UserPreferences.mediaBarEnabled.key)
    }

    // MARK: - Theme sync

    private func fetchThemesPayload(client: HttpClient) async -> Any? {
        guard let baseURL = client.baseURL else { return nil }

        let components = URLComponents(url: baseURL.appendingPathComponent(PluginSyncConstants.themesPath), resolvingAgainstBaseURL: false)
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(client.authorizationHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    private func extractThemeObjects(_ payload: Any?) -> [Any] {
        guard let payload else { return [] }

        if let list = payload as? [Any] {
            return list
        }

        if let map = payload as? [String: Any] {
            if let themes = map["themes"] as? [Any] {
                return themes
            }
            if let items = map["items"] as? [Any] {
                return items
            }
            let mapValues = map.values.filter { $0 is [String: Any] }
            if !mapValues.isEmpty {
                return mapValues
            }
        }

        return []
    }

    private func refreshCustomThemes(client: HttpClient) async {
        let payload = await fetchThemesPayload(client: client)
        let objects = extractThemeObjects(payload)

        var specs: [ThemeSpec] = []
        for entry in objects {
            guard let map = entry as? [String: Any] else { continue }
            do {
                let spec = try ThemeSpec.parse(jsonObject: map)
                if ThemeRegistry.builtInIds.contains(spec.id) {
                    continue
                }
                specs.append(spec)
            } catch {
                // Ignore malformed theme entries from plugin response.
            }
        }

        ThemeRegistry.shared.replaceCustomThemes(specs)

        let customThemeId = defaults.string(forKey: UserPreferences.customThemeId.key) ?? ""
        if !customThemeId.isEmpty && ThemeRegistry.shared.availableThemes[customThemeId] == nil {
            defaults.set("", forKey: UserPreferences.customThemeId.key)
        }
    }

    private func normalizedVisualThemeString(_ raw: Any) -> String {
        let value = "\(raw)"
        switch value {
        case "neon_pulse", "neonPulse":
            return VisualThemeId.neonPulse.rawValue
        default:
            return VisualThemeId.moonfin.rawValue
        }
    }

    // MARK: - List helpers

    private func readListValue(_ sp: SyncablePreference, store: UserDefaults) -> Any {
        switch sp.source {
        case .parental:
            if let data = store.data(forKey: sp.key),
               let set = try? JSONDecoder().decode(Set<String>.self, from: data) {
                return Array(set)
            }
            return sp.defaultValue
        default:
            if sp.key == UserPreferences.homeSections.key {
                let raw = store.string(forKey: sp.key) ?? ""
                if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return sp.defaultValue }

                let configs = HomeSectionConfig.fromStorageString(raw)
                return configs
                    .filter { $0.isBuiltin && $0.enabled && $0.type != .none && $0.type != .mediaBar }
                    .sorted { $0.order < $1.order }
                    .map { $0.type.serverName }
            }
            return store.stringArray(forKey: sp.key) ?? sp.defaultValue
        }
    }

    private func writeListValue(_ sp: SyncablePreference, value: Any, store: UserDefaults) {
        let list: [String]
        if let arr = value as? [String] {
            list = arr
        } else if let arr = value as? [Any] {
            list = arr.map { "\($0)" }
        } else if let csv = value as? String {
            list = csv
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            return
        }

        switch sp.source {
        case .parental:
            let set = Set(list)
            if let data = try? JSONEncoder().encode(set) {
                store.set(data, forKey: sp.key)
            }
        default:
            if sp.key == UserPreferences.homeSections.key {
                let existingConfigs = HomeSectionConfig.fromStorageString(store.string(forKey: sp.key) ?? "")
                let existingBuiltinByType = Dictionary(
                    uniqueKeysWithValues: existingConfigs
                        .filter(\.isBuiltin)
                        .map { ($0.type, $0) }
                )
                let existingPluginConfigs = existingConfigs
                    .filter(\.isPluginDynamic)
                    .sorted { $0.order < $1.order }

                var seen = Set<HomeSectionType>()
                let orderedEnabledTypes = list
                    .compactMap { HomeSectionType.from(serverName: $0) }
                    .filter { $0 != .none && $0 != .mediaBar }
                    .filter { seen.insert($0).inserted }

                var merged: [HomeSectionConfig] = []

                for type in orderedEnabledTypes {
                    var config = existingBuiltinByType[type] ?? HomeSectionConfig.builtin(type: type, enabled: true, order: 0)
                    config.kind = .builtin
                    config.enabled = true
                    config.order = merged.count
                    config.serverId = nil
                    config.pluginSection = nil
                    config.pluginAdditionalData = nil
                    config.pluginDisplayText = nil
                    config.pluginSource = .hss
                    merged.append(config)
                }

                for type in HomeSectionType.allCases where type != .none && type != .mediaBar {
                    guard !seen.contains(type) else { continue }
                    var config = existingBuiltinByType[type] ?? HomeSectionConfig.builtin(type: type, enabled: false, order: 0)
                    config.kind = .builtin
                    config.enabled = false
                    config.order = merged.count
                    config.serverId = nil
                    config.pluginSection = nil
                    config.pluginAdditionalData = nil
                    config.pluginDisplayText = nil
                    config.pluginSource = .hss
                    merged.append(config)
                }

                var nextOrder = merged.count
                for plugin in existingPluginConfigs {
                    var config = plugin
                    config.order = nextOrder
                    nextOrder += 1
                    merged.append(config)
                }

                store.set(HomeSectionConfig.toStorageString(merged), forKey: sp.key)
            } else {
                store.set(list, forKey: sp.key)
            }
        }
    }

    // MARK: - Three-way merge

    private func mergeThreeWay(local: [String: Any], server: [String: Any], snapshot: [String: Any]) -> [String: Any] {
        if snapshot.isEmpty {
            return local.merging(server) { _, server in server }
        }

        let allKeys = Set(local.keys).union(server.keys).union(snapshot.keys)
            .filter { PluginSyncConstants.allServerKeys.contains($0) }

        var merged = [String: Any]()
        for key in allKeys {
            let localVal = normalize(local[key])
            let serverVal = normalize(server[key])
            let snapshotVal = normalize(snapshot[key])

            let localChanged = localVal != snapshotVal
            let serverChanged = serverVal != snapshotVal

            if serverChanged && !localChanged {
                merged[key] = server[key] ?? local[key]
            } else {
                merged[key] = local[key] ?? server[key]
            }
        }
        return merged
    }

    private func normalize(_ value: Any?) -> String {
        guard let value else { return "" }
        if let arr = value as? [Any] {
            return arr.map { "\($0)" }.joined(separator: ",")
        }
        return "\(value)"
    }

    // MARK: - Snapshot

    private var snapshotDefaults: UserDefaults {
        UserDefaults(suiteName: PluginSyncConstants.snapshotKey) ?? defaults
    }

    private func loadSnapshot() -> [String: Any] {
        let snap = snapshotDefaults
        let savedVersion = snap.integer(forKey: PluginSyncConstants.snapshotVersionKey)
        if savedVersion < PluginSyncConstants.snapshotVersion {
            clearSnapshot()
            return [:]
        }

        var map = [String: Any]()
        for key in PluginSyncConstants.allServerKeys {
            if let value = snap.object(forKey: key) {
                map[key] = value
            }
        }
        return map
    }

    private func saveSnapshot(_ settings: [String: Any]) {
        let snap = snapshotDefaults
        for key in PluginSyncConstants.allServerKeys {
            snap.removeObject(forKey: key)
        }
        snap.set(PluginSyncConstants.snapshotVersion, forKey: PluginSyncConstants.snapshotVersionKey)
        for (key, value) in settings where PluginSyncConstants.allServerKeys.contains(key) {
            snap.set(value, forKey: key)
        }
    }

    private func clearSnapshot() {
        let snap = snapshotDefaults
        for key in PluginSyncConstants.allServerKeys {
            snap.removeObject(forKey: key)
        }
        snap.removeObject(forKey: PluginSyncConstants.snapshotVersionKey)
    }

    // MARK: - Change listener

    private func registerChangeListener() {
        unregisterChangeListener()

        changeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDefaultsChange()
            }
        }

        if let seerr = seerrDefaults() {
            seerrChangeObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: seerr,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDefaultsChange()
                }
            }
        }

        if let parental = parentalDefaults() {
            parentalChangeObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: parental,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDefaultsChange()
                }
            }
        }
    }

    func unregisterChangeListener() {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
        if let observer = seerrChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            seerrChangeObserver = nil
        }
        if let observer = parentalChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            parentalChangeObserver = nil
        }
        pushTask?.cancel()
        pushTask = nil
        sseTask?.cancel()
        sseTask = nil
    }

    private func handleDefaultsChange() {
        guard defaults.bool(forKey: UserPreferences.pluginSyncEnabled.key),
              isPluginAvailable else { return }

        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(nanoseconds: PluginSyncConstants.debounceMs * 1_000_000)
            guard !Task.isCancelled else { return }

            guard let client = resolveClient(), client.isUsable else { return }
            let settings = collectLocalSettings()
            await pushSettings(client: client, settings: settings)
            saveSnapshot(settings)
        }
    }

    // MARK: - Seerr row config sync

    private static let serverKeyToSeerrRow: [String: SeerrRowType] = {
        var map: [String: SeerrRowType] = [:]
        for type in SeerrRowType.allCases {
            map[type.rawValue] = type
        }
        map["trendingMovies"] = .trending
        map["trendingTv"] = .trending
        map["popularMovies"] = .popularMovies
        map["popularTv"] = .popularSeries
        map["movieGenres"] = .movieGenres
        map["upcomingMovies"] = .upcomingMovies
        map["upcomingTv"] = .upcomingSeries
        map["recentRequests"] = .recentRequests
        map["recentlyAdded"] = .recentlyAdded
        return map
    }()

    private func applySeerrRowConfig() {
        guard let config = pendingSeerrRowsConfig else { return }
        guard let seerr = seerrDefaults() else { return }
        pendingSeerrRowsConfig = nil

        let rowOrder = (config["rowOrder"] as? [String]) ?? []

        var orderedTypes: [SeerrRowType] = []
        var seen = Set<SeerrRowType>()
        for key in rowOrder {
            if let rowType = Self.serverKeyToSeerrRow[key], !seen.contains(rowType) {
                seen.insert(rowType)
                orderedTypes.append(rowType)
            }
        }

        let enabledSet = seen
        for type in SeerrRowType.allCases where !seen.contains(type) {
            orderedTypes.append(type)
        }

        let configs: [SeerrRowConfig] = orderedTypes.enumerated().map { index, type in
            SeerrRowConfig(type: type, enabled: enabledSet.contains(type), order: index)
        }

        if let data = try? JSONEncoder().encode(configs),
           let json = String(data: data, encoding: .utf8) {
            seerr.set(json, forKey: SeerrPreferences.rowsConfigJson.key)
        }
    }

    private func collectSeerrRowsConfig() -> [String: Any]? {
        guard let seerr = seerrDefaults() else { return nil }
        let json = seerr.string(forKey: SeerrPreferences.rowsConfigJson.key) ?? ""
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let configs = try? JSONDecoder().decode([SeerrRowConfig].self, from: data) else { return nil }

        let activeRows = configs
            .sorted { $0.order < $1.order }
            .filter(\.enabled)
            .map(\.type.rawValue)

        guard !activeRows.isEmpty else { return nil }
        return ["rowOrder": activeRows]
    }

    // MARK: - Per-user Seerr defaults

    private func seerrDefaults() -> UserDefaults? {
        guard let userId = resolveClient()?.userId else { return nil }
        return UserDefaults(suiteName: "seerr_prefs_\(userId)")
    }

    private func parentalDefaults() -> UserDefaults? {
        guard let userId = resolveClient()?.userId else { return nil }
        return UserDefaults(suiteName: "parental_controls_\(userId)")
    }

    private func defaultsForPreference(_ sp: SyncablePreference) -> UserDefaults {
        switch sp.source {
        case .user:
            return defaults
        case .seerr:
            return seerrDefaults() ?? defaults
        case .parental:
            return parentalDefaults() ?? defaults
        }
    }

    // MARK: - Jellyseerr config

    private func configureJellyseerrProxy(client: HttpClient) async {
        guard let baseURL = client.baseURL else { return }

        await fetchJellyseerrConfig(client: client)

        guard let seerrRepo = resolveSeerrRepository() else { return }
        do {
            _ = try await seerrRepo.configureWithMoonfin(
                jellyfinBaseUrl: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                jellyfinToken: client.accessToken ?? ""
            )
        } catch { }
    }

    private func fetchJellyseerrConfig(client: HttpClient) async {
        guard let baseURL = client.baseURL else { return }

        let components = URLComponents(
            url: baseURL.appendingPathComponent(PluginSyncConstants.jellyseerrConfigPath),
            resolvingAgainstBaseURL: false
        )
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(client.authorizationHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let camelCased = json.reduce(into: [String: Any]()) { $0[toCamelCase($1.key)] = $1.value }

            let enabled = camelCased["enabled"] as? Bool ?? false
            let serverUrl = camelCased["url"] as? String
            let rawVariant = camelCased["variant"] as? String
            let variant = SeerrPreferences.normalizeVariant(rawVariant)
            let displayName = camelCased["displayName"] as? String

            guard let seerr = seerrDefaults() else { return }

            seerr.set(variant, forKey: SeerrPreferences.moonfinVariant.key)
            if let displayName, !displayName.isEmpty {
                seerr.set(displayName, forKey: SeerrPreferences.moonfinDisplayName.key)
            }

            if enabled, let serverUrl, !serverUrl.isEmpty {
                seerr.set(serverUrl, forKey: SeerrPreferences.serverUrl.key)
            }
        } catch { }
    }

    // MARK: - Helpers

    private func toCamelCase(_ key: String) -> String {
        guard !key.isEmpty else { return key }
        return key.prefix(1).lowercased() + key.dropFirst()
    }
}
