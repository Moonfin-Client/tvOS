import UIKit

@MainActor
class TrickPlayImageLoader: ObservableObject {
    @Published var thumbnail: UIImage?

    private var currentUrl: String?
    private var currentRect: CGRect?
    private var loadTask: Task<Void, Never>?
    private static let tileCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 20
        return cache
    }()

    func load(tile: TrickPlayTile) {
        if tile.imageUrl == currentUrl && tile.sourceRect == currentRect {
            return
        }
        currentUrl = tile.imageUrl
        currentRect = tile.sourceRect

        loadTask?.cancel()
        loadTask = Task {
            let cacheKey = tile.imageUrl as NSString
            let tileImage: UIImage

            if let cached = Self.tileCache.object(forKey: cacheKey) {
                tileImage = cached
            } else {
                guard let image = await fetchTileImage(url: tile.imageUrl, headers: tile.headers) else {
                    return
                }
                if Task.isCancelled { return }
                Self.tileCache.setObject(image, forKey: cacheKey)
                tileImage = image
            }

            guard !Task.isCancelled,
                  let cgImage = tileImage.cgImage,
                  let cropped = cgImage.cropping(to: tile.sourceRect) else { return }

            if tile.imageUrl == self.currentUrl && tile.sourceRect == self.currentRect {
                self.thumbnail = UIImage(cgImage: cropped)
            }
        }
    }

    func clear() {
        loadTask?.cancel()
        loadTask = nil
        thumbnail = nil
        currentUrl = nil
        currentRect = nil
    }

    private func fetchTileImage(url: String, headers: [String: String]) async -> UIImage? {
        guard let requestUrl = URL(string: url) else { return nil }
        var request = URLRequest(url: requestUrl)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
