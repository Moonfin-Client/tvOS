import Combine

@MainActor
final class HomeInfoState: ObservableObject {
    @Published var selectedItemState: SelectedItemState = .empty
}
