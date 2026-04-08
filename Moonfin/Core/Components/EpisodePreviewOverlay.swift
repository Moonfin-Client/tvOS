import SwiftUI

struct EpisodePreviewOverlay: View {
    let item: ServerItem
    let shouldPlay: Bool
    let muted: Bool

    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var previewManager: PreviewPlayerManager

    private var isActiveItem: Bool {
        previewManager.currentItemId == item.id
    }

    var body: some View {
        Group {
            if isActiveItem {
                PlaybackSurfaceView(player: previewManager.player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .opacity(previewManager.isVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.6), value: previewManager.isVisible)
            }
        }
        .onChange(of: shouldPlay) { newValue in
            if newValue {
                previewManager.requestPreview(for: item, muted: muted, container: container)
            } else {
                previewManager.stopIfCurrent(itemId: item.id)
            }
        }
        .onDisappear {
            previewManager.stopIfCurrent(itemId: item.id)
        }
    }
}
