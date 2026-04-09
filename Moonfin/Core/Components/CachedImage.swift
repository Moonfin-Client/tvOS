import SwiftUI
import NukeUI
import Nuke

/// A performant cached image view using Nuke's pipeline with memory + disk caching.
/// Replaces raw `AsyncImage` throughout the app to avoid redundant network fetches
/// and reduce image decoding on the main thread.
struct CachedImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var transaction: Transaction = Transaction(animation: .easeIn(duration: 0.15))
    var processors: [any ImageProcessing] = []
    var thumbnailSize: CGSize?

    var body: some View {
        LazyImage(request: imageRequest, transaction: transaction) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
    }

    private var imageRequest: ImageRequest? {
        guard let url else { return nil }
        var allProcessors = processors
        if let size = thumbnailSize {
            let scale = UIScreen.main.scale
            let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
            allProcessors.insert(ImageProcessors.Resize(size: pixelSize, contentMode: .aspectFill), at: 0)
        }
        if allProcessors.isEmpty {
            return ImageRequest(url: url)
        }
        return ImageRequest(url: url, processors: allProcessors)
    }
}

extension CachedImage {
    init(urlString: String?, contentMode: ContentMode = .fill, processors: [any ImageProcessing] = [], thumbnailSize: CGSize? = nil) {
        self.url = urlString.flatMap { URL(string: $0) }
        self.contentMode = contentMode
        self.processors = processors
        self.thumbnailSize = thumbnailSize
    }
}

// MARK: - Global Pipeline Configuration

enum ImagePipelineConfig {
    /// Call once at app launch to set up the shared Nuke pipeline.
    static func configure() {
        let pipeline = ImagePipeline {
            $0.imageCache = ImageCache(costLimit: 50 * 1024 * 1024, countLimit: 200)

            let dataCache = try? DataCache(name: "com.moonfin.images")
            dataCache?.sizeLimit = 250 * 1024 * 1024
            $0.dataCache = dataCache

            $0.isDecompressionEnabled = true
            $0.dataLoadingQueue.maxConcurrentOperationCount = 4
            $0.imageDecompressingQueue.maxConcurrentOperationCount = 3
        }
        ImagePipeline.shared = pipeline
    }
}
