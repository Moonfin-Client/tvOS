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
        if processors.isEmpty {
            return ImageRequest(url: url)
        }
        return ImageRequest(url: url, processors: processors)
    }
}

extension CachedImage {
    init(urlString: String?, contentMode: ContentMode = .fill, processors: [any ImageProcessing] = []) {
        self.url = urlString.flatMap { URL(string: $0) }
        self.contentMode = contentMode
        self.processors = processors
    }
}

// MARK: - Global Pipeline Configuration

enum ImagePipelineConfig {
    /// Call once at app launch to set up the shared Nuke pipeline.
    static func configure() {
        let pipeline = ImagePipeline {
            $0.imageCache = ImageCache(costLimit: 100 * 1024 * 1024, countLimit: 200)

            let dataCache = try? DataCache(name: "com.moonfin.images")
            dataCache?.sizeLimit = 250 * 1024 * 1024
            $0.dataCache = dataCache

            $0.isDecompressionEnabled = true
            $0.dataLoadingQueue.maxConcurrentOperationCount = 6
            $0.imageDecompressingQueue.maxConcurrentOperationCount = 2
        }
        ImagePipeline.shared = pipeline
    }
}
