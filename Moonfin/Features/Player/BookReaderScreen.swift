import SwiftUI

struct BookReaderScreen: View {
    @StateObject private var viewModel: BookReaderViewModel

    init(container: AppContainer, itemId: String, serverId: String?) {
        _viewModel = StateObject(wrappedValue: BookReaderViewModel(
            container: container,
            itemId: itemId,
            serverId: serverId
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
            } else if let message = viewModel.errorMessage {
                Text(message)
                    .font(.bodyLg)
                    .foregroundColor(.white.opacity(0.9))
            } else if let image = viewModel.currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, SpaceTokens.space3xl)
                    .padding(.vertical, SpaceTokens.space2xl)
            }

            if viewModel.overlayVisible && !viewModel.isLoading {
                overlay
            }
        }
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left:
                viewModel.goToPreviousPage()
            case .right:
                viewModel.goToNextPage()
            default:
                break
            }
            viewModel.showOverlay()
        }
        .onPlayPauseCommand {
            viewModel.showOverlay()
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    private var overlay: some View {
        VStack {
            HStack {
                Text(viewModel.title)
                    .font(.title2xl)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, SpaceTokens.space2xl)
            .padding(.top, SpaceTokens.space2xl)
            .padding(.bottom, SpaceTokens.spaceMd)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.8), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()

            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: "chevron.left")
                Text("Previous")
                Text("•")
                Text(viewModel.progressText)
                Text("•")
                Text("Next")
                Image(systemName: "chevron.right")
            }
            .font(.bodySm)
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, SpaceTokens.space2xl)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.65))
            )
            .padding(.bottom, SpaceTokens.space2xl)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.overlayVisible)
    }
}
