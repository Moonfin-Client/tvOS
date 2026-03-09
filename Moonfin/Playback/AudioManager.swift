import Foundation
import Combine

enum RepeatMode: String, CaseIterable {
    case off
    case one
    case all
}

enum PlaybackOrder: String, CaseIterable {
    case sequential
    case shuffle
}

@MainActor
final class AudioManager: ObservableObject {
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var playbackOrder: PlaybackOrder = .sequential

    let playbackManager: PlaybackManager
    private let client: MediaServerClient
    private var stateObserver: AnyCancellable?
    private var playHistory: [Int] = []

    var queue: [QueueEntry] { playbackManager.queue }
    var currentIndex: Int { playbackManager.currentIndex }
    var currentEntry: QueueEntry? { playbackManager.currentEntry }
    var player: VLCPlayerWrapper { playbackManager.player }

    var hasQueue: Bool { !queue.isEmpty }
    var currentItem: ServerItem? { currentEntry?.item }

    init(playbackManager: PlaybackManager, client: MediaServerClient) {
        self.playbackManager = playbackManager
        self.client = client
        playbackManager.autoAdvanceOnEnd = false
        observeState()
    }

    func playNow(items: [ServerItem], startIndex: Int = 0, shuffle: Bool = false) async {
        playHistory = []

        if shuffle {
            playbackOrder = .shuffle
            var shuffled = items
            shuffled.shuffle()
            if let startItem = items[safe: startIndex],
               let shuffledIdx = shuffled.firstIndex(where: { $0.id == startItem.id }) {
                shuffled.remove(at: shuffledIdx)
                shuffled.insert(startItem, at: 0)
            }
            await playbackManager.play(items: shuffled, startIndex: 0)
        } else {
            playbackOrder = .sequential
            await playbackManager.play(items: items, startIndex: startIndex)
        }
    }

    func addToQueue(items: [ServerItem]) {
        let newEntries = items.map { item in
            QueueEntry(id: item.id, item: item, mediaSourceId: item.mediaSources?.first?.id, startPositionTicks: 0)
        }
        var current = playbackManager.queue
        current.append(contentsOf: newEntries)
        playbackManager.replaceQueue(current)
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count && index != currentIndex else { return }
        var current = playbackManager.queue
        current.remove(at: index)
        playbackManager.replaceQueue(current)
    }

    func playEntry(at index: Int) async {
        playHistory.append(currentIndex)
        await playbackManager.playEntry(at: index)
    }

    func next() async {
        playHistory.append(currentIndex)

        if repeatMode == .one {
            await playbackManager.playEntry(at: currentIndex)
            return
        }

        if playbackOrder == .shuffle {
            let remaining = (0..<queue.count).filter { !playHistory.contains($0) && $0 != currentIndex }
            if let nextIdx = remaining.randomElement() {
                await playbackManager.playEntry(at: nextIdx)
            } else if repeatMode == .all {
                playHistory = []
                let nextIdx = (0..<queue.count).filter { $0 != currentIndex }.randomElement() ?? 0
                await playbackManager.playEntry(at: nextIdx)
            }
            return
        }

        if playbackManager.hasNext {
            await playbackManager.playNext()
        } else if repeatMode == .all {
            await playbackManager.playEntry(at: 0)
        }
    }

    func previous() async {
        if player.currentTime > 5 {
            playbackManager.seek(to: 0)
            return
        }

        if let prevIdx = playHistory.popLast() {
            await playbackManager.playEntry(at: prevIdx)
        } else if playbackManager.hasPrevious {
            await playbackManager.playPrevious()
        }
    }

    func toggleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .one
        case .one: repeatMode = .all
        case .all: repeatMode = .off
        }
    }

    func toggleShuffle() {
        playbackOrder = playbackOrder == .sequential ? .shuffle : .sequential
        playHistory = []
    }

    func stop() async {
        playHistory = []
        await playbackManager.stop()
    }

    func albumArtUrl(for item: ServerItem) -> URL? {
        let imageId: String
        let tag: String?

        if let albumId = item.albumId, let albumTag = item.albumPrimaryImageTag {
            imageId = albumId
            tag = albumTag
        } else if let primaryTag = item.imageTags?["Primary"] {
            imageId = item.id
            tag = primaryTag
        } else {
            return nil
        }

        let urlString = client.imageApi.getItemImageUrl(
            itemId: imageId,
            imageType: .primary,
            maxWidth: 600,
            maxHeight: 600,
            tag: tag
        )
        return URL(string: urlString)
    }

    private func observeState() {
        stateObserver = playbackManager.player.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] vlcState in
                guard let self else { return }
                if case .ended = vlcState {
                    Task { await self.next() }
                }
            }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
