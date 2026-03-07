import Foundation
import Combine

@MainActor
final class PluginSyncService: ObservableObject {
    @Published private(set) var isPluginAvailable = false
    @Published private(set) var syncCompletedCount = 0

    private let preferenceStore: PreferenceStore
    private let resolveClient: () -> HttpClient?
    private let defaults: UserDefaults

    private var serverSchemaVersion = 1
    private var pushTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?

    init(
        preferenceStore: PreferenceStore,
        resolveClient: @escaping () -> HttpClient?,
        defaults: UserDefaults = .standard
    ) {
        self.preferenceStore = preferenceStore
        self.resolveClient = resolveClient
        self.defaults = defaults
    }

    func syncOnStartup() async {
        let syncEnabled = defaults.bool(forKey: UserPreferences.pluginSyncEnabled.key)
        guard syncEnabled else {
            unregisterChangeListener()
            return
        }

        guard let client = resolveClient(), client.isUsable else { return }

        let available = await ping(client: client)
        isPluginAvailable = available
        guard available else { return }

        let serverSettings = await fetchServerSettings(client: client)
        let localSettings = collectLocalSettings()
        let snapshot = loadSnapshot()

        if let serverSettings {
            let merged = mergeThreeWay(local: localSettings, server: serverSettings, snapshot: snapshot)
            applySettings(merged)
            await pushSettings(client: client, settings: merged)
            saveSnapshot(merged)
            syncCompletedCount += 1
        } else {
            await pushSettings(client: client, settings: localSettings)
            saveSnapshot(localSettings)
        }

        registerChangeListener()
    }

    func initialSync() async {
        clearSnapshot()
        await syncOnStartup()
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
                let globalProfile = (json["Global"] as? [String: Any]) ?? (json["global"] as? [String: Any])
                let tvProfile = (json["Tv"] as? [String: Any]) ?? (json["tv"] as? [String: Any])
                return resolveV2Profile(global: globalProfile, tv: tvProfile)
            } else {
                return json.reduce(into: [String: Any]()) { result, pair in
                    result[toCamelCase(pair.key)] = pair.value
                }
            }
        } catch {
            return nil
        }
    }

    private func resolveV2Profile(global: [String: Any]?, tv: [String: Any]?) -> [String: Any] {
        var resolved = [String: Any]()

        if let global {
            for (key, value) in global {
                let camelKey = toCamelCase(key)
                if PluginSyncConstants.allServerKeys.contains(camelKey) {
                    resolved[camelKey] = value
                }
            }
        }

        if let tv {
            for (key, value) in tv {
                if value is NSNull { continue }
                let camelKey = toCamelCase(key)
                if PluginSyncConstants.allServerKeys.contains(camelKey) {
                    resolved[camelKey] = value
                }
            }
        }

        return resolved
    }

    // MARK: - Push

    private func pushSettings(client: HttpClient, settings: [String: Any]) async {
        guard let baseURL = client.baseURL else { return }

        let path: String
        let bodyDict: [String: Any]

        if serverSchemaVersion >= 2 {
            path = "\(PluginSyncConstants.settingsPath)/Profile/global"
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
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("[PluginSync] Push failed (\(http.statusCode))")
            }
        } catch {
            print("[PluginSync] Push failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Collect local

    private func collectLocalSettings() -> [String: Any] {
        var map = [String: Any]()
        for sp in PluginSyncConstants.syncablePreferences {
            map[sp.serverKey] = readLocalValue(sp)
        }
        return map
    }

    private func readLocalValue(_ sp: SyncablePreference) -> Any {
        guard defaults.object(forKey: sp.key) != nil else { return sp.defaultValue }

        switch sp.type {
        case .boolean:
            return defaults.bool(forKey: sp.key)
        case .int:
            return defaults.integer(forKey: sp.key)
        case .string, .enum:
            return defaults.string(forKey: sp.key) ?? sp.defaultValue
        }
    }

    // MARK: - Apply

    private func applySettings(_ settings: [String: Any]) {
        for (serverKey, value) in settings {
            guard let sp = PluginSyncConstants.serverToLocal[serverKey] else { continue }
            writeLocalValue(sp, value: value)
        }
    }

    private func writeLocalValue(_ sp: SyncablePreference, value: Any) {
        switch sp.type {
        case .boolean:
            if let b = value as? Bool {
                defaults.set(b, forKey: sp.key)
            } else if let s = value as? String, let b = Bool(s) {
                defaults.set(b, forKey: sp.key)
            } else if let n = value as? NSNumber {
                defaults.set(n.boolValue, forKey: sp.key)
            }
        case .int:
            if let i = value as? Int {
                defaults.set(i, forKey: sp.key)
            } else if let n = value as? NSNumber {
                defaults.set(n.intValue, forKey: sp.key)
            } else if let s = value as? String, let i = Int(s) {
                defaults.set(i, forKey: sp.key)
            }
        case .string, .enum:
            defaults.set("\(value)", forKey: sp.key)
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
            self?.handleDefaultsChange()
        }
    }

    func unregisterChangeListener() {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
        pushTask?.cancel()
        pushTask = nil
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

    // MARK: - Helpers

    private func toCamelCase(_ key: String) -> String {
        guard !key.isEmpty else { return key }
        return key.prefix(1).lowercased() + key.dropFirst()
    }
}
