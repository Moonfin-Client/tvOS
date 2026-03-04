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

    func switchFlow(to flow: AppFlow) {
        self.flow = flow
        path = NavigationPath()
    }
}
