import SwiftUI

enum AppFlow: Hashable {
    case splash
    case startup
    case main
}

@MainActor
final class NavigationRouter: ObservableObject {
    @Published var flow: AppFlow = .splash
    @Published var path = NavigationPath()
    @Published var startupPath = NavigationPath()
    @Published var hideNavbar = false
    @Published var isPlaybackActive = false
    private var navbarHideRequestCount = 0
    private var playbackActiveRequestCount = 0

    func pushNavbarHidden() {
        navbarHideRequestCount += 1
        hideNavbar = true
    }

    func popNavbarHidden() {
        guard navbarHideRequestCount > 0 else {
            resetNavbarVisibility()
            return
        }
        navbarHideRequestCount -= 1
        hideNavbar = navbarHideRequestCount > 0
    }

    func resetNavbarVisibility() {
        navbarHideRequestCount = 0
        hideNavbar = false
    }

    func pushPlaybackActive() {
        playbackActiveRequestCount += 1
        isPlaybackActive = true
    }

    func popPlaybackActive() {
        guard playbackActiveRequestCount > 0 else {
            resetPlaybackActive()
            return
        }
        playbackActiveRequestCount -= 1
        isPlaybackActive = playbackActiveRequestCount > 0
    }

    func resetPlaybackActive() {
        playbackActiveRequestCount = 0
        isPlaybackActive = false
    }

    private var activePath: NavigationPath {
        get { flow == .startup ? startupPath : path }
        set {
            if flow == .startup { startupPath = newValue }
            else { path = newValue }
        }
    }

    func navigate(to destination: Destination) {
        activePath.append(destination)
    }

    func goBack() {
        guard !activePath.isEmpty else { return }
        activePath.removeLast()
    }

    func goBack(count: Int) {
        let removeCount = min(count, activePath.count)
        guard removeCount > 0 else { return }
        activePath.removeLast(removeCount)
    }

    func reset(to destination: Destination? = nil) {
        activePath = NavigationPath()
        if let destination { activePath.append(destination) }
    }

    func navigatePrimary(to destination: Destination) {
        reset(to: destination)
    }

    func navigateToItem(_ item: ServerItem, serverId: String? = nil) {
        if isPhotoItem(item) {
            navigate(to: .photoPlayer(itemId: item.id, autoPlay: false))
            return
        }

        if isFolderLike(item) {
            navigateToLibrary(item)
            return
        }

        if isBookItem(item) {
            navigate(to: .bookReader(itemId: item.id, serverId: serverId ?? item.effectiveServerId))
            return
        }

        navigate(to: .itemDetails(itemId: item.id, serverId: serverId ?? item.effectiveServerId))
    }

    func navigatePrimaryToItem(_ item: ServerItem, serverId: String? = nil) {
        if isPhotoItem(item) {
            navigatePrimary(to: .photoPlayer(itemId: item.id, autoPlay: false))
            return
        }

        if isFolderLike(item) {
            navigatePrimaryToLibrary(item)
            return
        }

        if isBookItem(item) {
            navigatePrimary(to: .bookReader(itemId: item.id, serverId: serverId ?? item.effectiveServerId))
            return
        }

        navigatePrimary(to: .itemDetails(itemId: item.id, serverId: serverId ?? item.effectiveServerId))
    }

    func navigateToItem(_ item: MediaBarSlideItem) {
        if isPhotoItem(item) {
            navigate(to: .photoPlayer(itemId: item.id, autoPlay: false))
            return
        }

        if isBookItem(item) {
            navigate(to: .bookReader(itemId: item.id, serverId: item.serverId))
            return
        }

        navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId))
    }

    private func isPhotoItem(_ item: ServerItem) -> Bool {
        item.type == .photo || item.mediaType == .photo
    }

    private func isPhotoItem(_ item: MediaBarSlideItem) -> Bool {
        item.itemType == .photo
    }

    private static let detailFolderTypes: Set<ItemType> = [
        .series, .season, .musicAlbum, .musicArtist, .albumArtist, .boxSet, .playlist, .photoAlbum
    ]

    private func isFolderLike(_ item: ServerItem) -> Bool {
        if Self.detailFolderTypes.contains(item.type) {
            return false
        }

        if item.isFolder == true {
            return true
        }

        if [.folder, .collectionFolder, .userView, .basePluginFolder].contains(item.type) {
            return true
        }

        if (item.collectionType?.isEmpty == false) && (item.childCount ?? 0) > 0 {
            return true
        }

        if (item.type == .book || item.mediaType == .book) && (item.childCount ?? 0) > 0 {
            return true
        }

        return false
    }

    private func isBookItem(_ item: ServerItem) -> Bool {
        (item.type == .book || item.mediaType == .book) && item.isFolder != true
    }

    private func isBookItem(_ item: MediaBarSlideItem) -> Bool {
        item.itemType == .book
    }

    func navigatePrimaryToLibrary(_ item: ServerItem) {
        switch item.collectionType?.lowercased() {
        case "music":
            navigatePrimary(to: .musicBrowser(itemId: item.id))
        case "livetv":
            navigatePrimary(to: .liveTvGuide)
        default:
            navigatePrimary(to: .libraryBrowser(itemId: item.id))
        }
    }

    func navigateToLibrary(_ item: ServerItem) {
        switch item.collectionType?.lowercased() {
        case "music":
            navigate(to: .musicBrowser(itemId: item.id))
        case "livetv":
            navigate(to: .liveTvGuide)
        default:
            navigate(to: .libraryBrowser(itemId: item.id))
        }
    }

    func switchFlow(to flow: AppFlow) {
        self.flow = flow
        path = NavigationPath()
        startupPath = NavigationPath()
        resetNavbarVisibility()
    }
}
