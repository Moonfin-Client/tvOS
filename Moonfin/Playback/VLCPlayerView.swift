import SwiftUI
import UIKit

struct VLCPlayerView: UIViewRepresentable {
    let player: VLCPlayerWrapper

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isOpaque = true
        view.layer.isDoubleSided = false
        player.attachVideoView(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        uiView.layer.contents = nil
    }
}

extension VLCPlayerView: Equatable {
    static func == (lhs: VLCPlayerView, rhs: VLCPlayerView) -> Bool {
        lhs.player === rhs.player
    }
}
