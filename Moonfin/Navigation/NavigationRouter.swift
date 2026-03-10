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
    }
}
