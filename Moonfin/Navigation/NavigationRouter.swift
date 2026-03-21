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
    @Published var hideNavbar = false
    private var navbarHideRequestCount = 0

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

    func navigate(to destination: Destination) {
        path.append(destination)
    }

    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func goBack(count: Int) {
        let removeCount = min(count, path.count)
        guard removeCount > 0 else { return }
        path.removeLast(removeCount)
    }

    func reset(to destination: Destination? = nil) {
        path = NavigationPath()
        if let destination { path.append(destination) }
    }

    func navigatePrimary(to destination: Destination) {
        reset(to: destination)
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
        resetNavbarVisibility()
    }
}
