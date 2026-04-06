import SwiftUI
import UIKit

private class PlayerHostView: UIView {
    var onWindowAttach: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onWindowAttach?()
            onWindowAttach = nil
        }
    }
}

struct PlaybackSurfaceView: UIViewRepresentable {
    let player: MpvPlayerWrapper

    func makeUIView(context: Context) -> UIView {
        let view = PlayerHostView()
        view.backgroundColor = .black
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isOpaque = true
        view.layer.isDoubleSided = false
        player.attachVideoView(view)
        view.onWindowAttach = { [weak player] in
            player?.notifySurfaceReady()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        uiView.layer.contents = nil
    }
}

extension PlaybackSurfaceView: Equatable {
    static func == (lhs: PlaybackSurfaceView, rhs: PlaybackSurfaceView) -> Bool {
        lhs.player === rhs.player
    }
}
