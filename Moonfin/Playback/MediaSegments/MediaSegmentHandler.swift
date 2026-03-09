import Foundation
import Combine

struct SegmentSkipAction {
    let segment: MediaSegmentDto
    let action: MediaSegmentAction
}

@MainActor
final class MediaSegmentHandler: ObservableObject {
    @Published var activeSkipPrompt: SegmentSkipAction?

    var skipTo: ((TimeInterval) -> Void)?

    private let repository: MediaSegmentRepository
    private var skipActions: [SegmentSkipAction] = []
    private var askToSkipActions: [SegmentSkipAction] = []
    private var triggeredSegments: Set<String> = []
    private var autoHideTask: Task<Void, Never>?

    init(repository: MediaSegmentRepository) {
        self.repository = repository
    }

    func loadSegments(for itemId: String) async {
        reset()
        let fetched = await repository.getSegmentsForItem(itemId: itemId)

        for segment in fetched {
            let action = repository.resolvedAction(for: segment)
            let skipAction = SegmentSkipAction(segment: segment, action: action)
            switch action {
            case .skip:
                skipActions.append(skipAction)
            case .askToSkip:
                askToSkipActions.append(skipAction)
            case .nothing:
                break
            }
        }
    }

    func onPositionUpdate(_ position: TimeInterval) {
        for action in skipActions {
            guard !triggeredSegments.contains(action.segment.id) else { continue }
            if position >= action.segment.startSeconds && position < action.segment.endSeconds {
                triggeredSegments.insert(action.segment.id)
                skipTo?(action.segment.endSeconds)
            }
        }

        for action in askToSkipActions {
            guard !triggeredSegments.contains(action.segment.id) else { continue }
            if position >= action.segment.startSeconds && position < action.segment.endSeconds {
                triggeredSegments.insert(action.segment.id)
                showSkipPrompt(action)
            }
        }

        if let prompt = activeSkipPrompt, position >= prompt.segment.endSeconds {
            dismissPrompt()
        }
    }

    func confirmSkip() {
        guard let prompt = activeSkipPrompt else { return }
        dismissPrompt()
        skipTo?(prompt.segment.endSeconds)
    }

    func dismissPrompt() {
        autoHideTask?.cancel()
        autoHideTask = nil
        activeSkipPrompt = nil
    }

    func reset() {
        dismissPrompt()
        skipActions = []
        askToSkipActions = []
        triggeredSegments = []
    }

    private func showSkipPrompt(_ action: SegmentSkipAction) {
        activeSkipPrompt = action
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(MediaSegmentRepositoryImpl.askToSkipAutoHideDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            activeSkipPrompt = nil
        }
    }
}
