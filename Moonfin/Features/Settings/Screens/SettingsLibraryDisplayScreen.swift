import SwiftUI

struct SettingsLibraryDisplayScreen: View {
    let itemId: String
    let displayPreferencesId: String
    let serverId: String
    let userId: String

    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    @State private var isHiddenFromNavbar = false
    @State private var userConfigJSON: [String: Any]? = nil

    private var prefs: LibraryPreferences {
        LibraryPreferences(store: container.preferenceStore, libraryId: itemId)
    }

    var body: some View {
        SettingsScreenLayout(title: "Display Settings") {
            SettingsToggleButton(
                icon: "eye.slash",
                heading: "Hide from Home",
                caption: "Exclude this library from the home screen navbar",
                isOn: Binding(
                    get: { isHiddenFromNavbar },
                    set: { newValue in
                        isHiddenFromNavbar = newValue
                        Task { await saveHiddenState(hidden: newValue) }
                    }
                )
            )
            SettingsListButton(
                icon: "rectangle.expand.vertical",
                heading: "Image Size",
                caption: "Size of cards in the grid",
                trailingText: prefs.posterSize.displayName,
                action: {
                    settingsRouter.navigate(to: .librariesDisplayImageSize(
                        itemId: itemId,
                        displayPreferencesId: displayPreferencesId,
                        serverId: serverId,
                        userId: userId
                    ))
                }
            )
            .focused($focusedRoute, equals: .librariesDisplayImageSize(
                itemId: itemId,
                displayPreferencesId: displayPreferencesId,
                serverId: serverId,
                userId: userId
            ))

            SettingsListButton(
                icon: "photo",
                heading: "Image Type",
                caption: "Type of image shown on cards",
                trailingText: prefs.imageType.displayName,
                action: {
                    settingsRouter.navigate(to: .librariesDisplayImageType(
                        itemId: itemId,
                        displayPreferencesId: displayPreferencesId,
                        serverId: serverId,
                        userId: userId
                    ))
                }
            )
            .focused($focusedRoute, equals: .librariesDisplayImageType(
                itemId: itemId,
                displayPreferencesId: displayPreferencesId,
                serverId: serverId,
                userId: userId
            ))

            SettingsListButton(
                icon: "arrow.up.arrow.down",
                heading: "Grid Direction",
                caption: "Scroll orientation for the grid",
                trailingText: prefs.gridDirection.displayName,
                action: {
                    settingsRouter.navigate(to: .librariesDisplayGrid(
                        itemId: itemId,
                        displayPreferencesId: displayPreferencesId,
                        serverId: serverId,
                        userId: userId
                    ))
                }
            )
            .focused($focusedRoute, equals: .librariesDisplayGrid(
                itemId: itemId,
                displayPreferencesId: displayPreferencesId,
                serverId: serverId,
                userId: userId
            ))
        }
        .restoresFocus($focusedRoute)
        .task { await loadHiddenState() }
    }

    private func makeHttpClient() -> HttpClient? {
        guard let routeServerId = UUID(uuidString: serverId),
              let routeUserId = UUID(uuidString: userId),
              let server = container.serverRepository.storedServers.value.first(where: { $0.id == routeServerId }) else {
            return nil
        }

        let accessToken: String
        if let currentSession = container.sessionRepository.currentSession.value,
           currentSession.serverId == routeServerId,
           currentSession.userId == routeUserId {
            accessToken = currentSession.accessToken
        } else if let token = container.authenticationStore.getUser(routeServerId, routeUserId)?.accessToken,
                  !token.isEmpty {
            accessToken = token
        } else {
            return nil
        }

        return container.serverClientFactory.configuredClient(
            for: server, accessToken: accessToken, userId: routeUserId.uuidString
        ).httpClient
    }

    private func loadHiddenState() async {
        guard let client = makeHttpClient() else { return }
        do {
            let data = try await client.requestData("/Users/\(userId)")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            userConfigJSON = json
            let config = json["Configuration"] as? [String: Any] ?? [:]
            let excludes = config["MyMediaExcludes"] as? [String] ?? []
            await MainActor.run { isHiddenFromNavbar = excludes.contains(itemId) }
        } catch {
            return
        }
    }

    private func saveHiddenState(hidden: Bool) async {
        guard let client = makeHttpClient(),
              var json = userConfigJSON,
              var config = json["Configuration"] as? [String: Any] else { return }
        var excludes = config["MyMediaExcludes"] as? [String] ?? []
        if hidden {
            if !excludes.contains(itemId) { excludes.append(itemId) }
        } else {
            excludes.removeAll { $0 == itemId }
        }
        config["MyMediaExcludes"] = excludes
        json["Configuration"] = config
        userConfigJSON = json
        do {
            let configData = try JSONSerialization.data(withJSONObject: config)
            try await client.postRaw("/Users/\(userId)/Configuration", rawBody: configData)
        } catch {
            await loadHiddenState()
        }
    }
}
