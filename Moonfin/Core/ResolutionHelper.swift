import Foundation

enum ResolutionHelper {
    static func resolutionName(for item: ServerItem) -> String? {
        if let streams = item.mediaStreams ?? item.mediaSources?.first?.mediaStreams,
           let videoStream = streams.first(where: { $0.type == .video }) {
            if let fromDimensions = resolutionName(width: videoStream.width, height: videoStream.height) {
                return fromDimensions
            }
            if let displayTitle = videoStream.displayTitle,
               let fromDisplayTitle = resolutionName(fromText: displayTitle) {
                return fromDisplayTitle
            }
        }

        if let mediaSourceName = item.mediaSources?.first?.name,
           let fromSourceName = resolutionName(fromText: mediaSourceName) {
            return fromSourceName
        }

        return nil
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

    private static func resolutionName(fromText text: String) -> String? {
        let lowercased = text.lowercased()

        if lowercased.contains("8k") || lowercased.contains("4320") { return "8K" }
        if lowercased.contains("4k") || lowercased.contains("2160") { return "4K" }
        if lowercased.contains("1440") { return "1440p" }
        if lowercased.contains("1080") { return "1080p" }
        if lowercased.contains("720") { return "720p" }
        if lowercased.contains("480") { return "480p" }
        if lowercased.contains("sd") { return "SD" }

        return nil
    }
}
