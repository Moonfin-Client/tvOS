import Foundation

enum ResolutionHelper {
    static func resolutionName(for item: ServerItem) -> String? {
        guard let streams = item.mediaStreams ?? item.mediaSources?.first?.mediaStreams else { return nil }
        guard let videoStream = streams.first(where: { $0.type == .video }) else { return nil }
        return resolutionName(width: videoStream.width, height: videoStream.height)
    }

    static func resolutionName(width: Int?, height: Int?) -> String? {
        let w = width ?? 0
        let h = height ?? 0
        guard w > 0 || h > 0 else { return nil }

        if w >= 7600 || h >= 4300 { return "8K" }
        if w >= 3800 || h >= 2000 { return "4K" }
        if w >= 2500 || h >= 1400 { return "1440p" }
        if w >= 1800 || h >= 1000 { return "1080p" }
        if w >= 1200 || h >= 700 { return "720p" }
        if w >= 600 || h >= 400 { return "480p" }
        return "SD"
    }
}
