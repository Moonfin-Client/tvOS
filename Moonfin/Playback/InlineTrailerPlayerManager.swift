import Foundation
import Combine
import UIKit

@MainActor
final class InlineTrailerPlayerManager: ObservableObject {

    private static let idleTeardownNanoseconds: UInt64 = 30_000_000_000

    @Published private(set) var state: PlayerState = .idle

    private(set) var player: MpvPlayerWrapper?
    private var stateObserver: AnyCancellable?
    private var idleTeardownTask: Task<Void, Never>?

    let surface: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isOpaque = true
        return view
    }()

    private func ensurePlayer() -> MpvPlayerWrapper {
        if let existing = player { return existing }
        let created = MpvPlayerWrapper.makePlayer()
        created.attachVideoView(surface)
        if surface.window != nil {
            created.notifySurfaceReady()
        }
        player = created
        stateObserver = created.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState
            }
        return created
    }

    private func teardownPlayer() {
        stateObserver?.cancel()
        stateObserver = nil
        player?.stop()
        player = nil
        state = .idle
        surface.subviews.forEach { $0.removeFromSuperview() }
        surface.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    private func scheduleIdleTeardown() {
        idleTeardownTask?.cancel()
        idleTeardownTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleTeardownNanoseconds)
            guard !Task.isCancelled else { return }
            self?.teardownPlayer()
        }
    }

    private func cancelIdleTeardown() {
        idleTeardownTask?.cancel()
        idleTeardownTask = nil
    }

    func stop() {
        player?.stop()
        scheduleIdleTeardown()
    }

    func setMuted(_ muted: Bool) {
        cancelIdleTeardown()
        ensurePlayer().setMuted(muted)
    }

    func setProperty(_ name: String, value: String) {
        cancelIdleTeardown()
        ensurePlayer().setProperty(name, value: value)
    }

    func play(streamUrl: String) async {
        cancelIdleTeardown()
        let p = ensurePlayer()
        await p.play(streamUrl: streamUrl)
    }

    func play(url: URL) async {
        cancelIdleTeardown()
        let p = ensurePlayer()
        await p.play(url: url)
    }
}
