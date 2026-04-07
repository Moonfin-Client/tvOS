import SwiftUI
import UIKit

struct RemoteInputView: UIViewControllerRepresentable {
    let onSelect: () -> Void
    let onDirection: (UIPress.PressType) -> Void
    let onPlayPause: () -> Void
    let onMenu: () -> Void
    var focusToken: UUID

    func makeUIViewController(context: Context) -> RemoteInputController {
        let vc = RemoteInputController()
        vc.onSelect = onSelect
        vc.onDirection = onDirection
        vc.onPlayPause = onPlayPause
        vc.onMenu = onMenu
        return vc
    }

    func updateUIViewController(_ vc: RemoteInputController, context: Context) {
        vc.onSelect = onSelect
        vc.onDirection = onDirection
        vc.onPlayPause = onPlayPause
        vc.onMenu = onMenu
        vc.setNeedsFocusUpdate()
        vc.updateFocusIfNeeded()
    }
}

final class RemoteInputController: UIViewController {
    var onSelect: (() -> Void)?
    var onDirection: ((UIPress.PressType) -> Void)?
    var onPlayPause: (() -> Void)?
    var onMenu: (() -> Void)?

    override func loadView() {
        let v = FocusableView()
        v.backgroundColor = .clear
        self.view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let selectTap = UITapGestureRecognizer(target: self, action: #selector(handleSelect))
        selectTap.allowedPressTypes = [NSNumber(integerLiteral: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(selectTap)

        let playPauseTap = UITapGestureRecognizer(target: self, action: #selector(handlePlayPause))
        playPauseTap.allowedPressTypes = [NSNumber(integerLiteral: UIPress.PressType.playPause.rawValue)]
        view.addGestureRecognizer(playPauseTap)

        let menuTap = UITapGestureRecognizer(target: self, action: #selector(handleMenu))
        menuTap.allowedPressTypes = [NSNumber(integerLiteral: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuTap)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(focusMovementDidFail),
            name: UIFocusSystem.movementDidFailNotification,
            object: nil
        )
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [view] }

    @objc private func handleSelect() { onSelect?() }
    @objc private func handlePlayPause() { onPlayPause?() }
    @objc private func handleMenu() { onMenu?() }

    @objc private func focusMovementDidFail(_ notification: Notification) {
        guard view.window != nil else { return }
        guard let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
            as? UIFocusUpdateContext else { return }
        let heading = context.focusHeading
        if heading.contains(.up) {
            onDirection?(.upArrow)
        } else if heading.contains(.down) {
            onDirection?(.downArrow)
        } else if heading.contains(.left) {
            onDirection?(.leftArrow)
        } else if heading.contains(.right) {
            onDirection?(.rightArrow)
        }
    }
}

private final class FocusableView: UIView {
    override var canBecomeFocused: Bool { true }
}
