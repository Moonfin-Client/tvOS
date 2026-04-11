import CoreGraphics
import Foundation

struct TrickPlayInfo: Codable {
    let width: Int
    let height: Int
    let tileWidth: Int
    let tileHeight: Int
    let thumbnailCount: Int
    let interval: Int
    let bandwidth: Int

    var tilesPerImage: Int { tileWidth * tileHeight }
    var isValid: Bool {
        width > 0 && height > 0 && tileWidth > 0 && tileHeight > 0 && interval > 0
    }

    enum CodingKeys: String, CodingKey {
        case width = "Width"
        case height = "Height"
        case tileWidth = "TileWidth"
        case tileHeight = "TileHeight"
        case thumbnailCount = "ThumbnailCount"
        case interval = "Interval"
        case bandwidth = "Bandwidth"
    }
}

struct TrickPlayTile {
    let imageUrl: String
    let headers: [String: String]
    let sourceRect: CGRect
    let thumbSize: CGSize
}

func trickPlayTile(
    positionMs: Int,
    info: TrickPlayInfo,
    itemId: String,
    mediaSourceId: String?,
    baseUrl: String,
    accessToken: String?
) -> TrickPlayTile? {
    guard info.isValid, positionMs >= 0 else { return nil }

    let tileIndex = min(positionMs / info.interval, max(info.thumbnailCount - 1, 0))
    let tilesPerImage = info.tilesPerImage
    let tileOffset = tileIndex % tilesPerImage
    let imageIndex = tileIndex / tilesPerImage

    let col = tileOffset % info.tileWidth
    let row = tileOffset / info.tileWidth
    let offsetX = CGFloat(col * info.width)
    let offsetY = CGFloat(row * info.height)

    let url = "\(baseUrl)/Videos/\(itemId)/Trickplay/\(info.width)/\(imageIndex).jpg"
        + (mediaSourceId.map { "?mediaSourceId=\($0)" } ?? "")

    var headers: [String: String] = [:]
    if let accessToken, !accessToken.isEmpty {
        headers["Authorization"] = "MediaBrowser Token=\"\(accessToken)\""
    }

    return TrickPlayTile(
        imageUrl: url,
        headers: headers,
        sourceRect: CGRect(x: offsetX, y: offsetY,
                           width: CGFloat(info.width), height: CGFloat(info.height)),
        thumbSize: CGSize(width: CGFloat(info.width), height: CGFloat(info.height))
    )
}
