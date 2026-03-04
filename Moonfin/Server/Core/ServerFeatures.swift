import Foundation

enum ServerFeature: String, CaseIterable {
    case quickConnect
    case syncPlay
    case watchParty
    case mediaSegments
    case trickplay
    case bifTrickplay
    case lyrics
    case clientLog
    case embyConnect
    case jellyseerr
}

protocol ServerFeatureSupport {
    var supportedFeatures: Set<ServerFeature> { get }
}

extension ServerFeatureSupport {
    func isSupported(_ feature: ServerFeature) -> Bool {
        supportedFeatures.contains(feature)
    }
}

struct JellyfinFeatureSupport: ServerFeatureSupport {
    let supportedFeatures: Set<ServerFeature> = [
        .quickConnect,
        .syncPlay,
        .mediaSegments,
        .trickplay,
        .lyrics,
        .clientLog,
        .jellyseerr,
    ]
}

struct EmbyFeatureSupport: ServerFeatureSupport {
    let supportedFeatures: Set<ServerFeature> = [
        .watchParty,
        .bifTrickplay,
        .embyConnect,
        .jellyseerr,
    ]
}

extension ServerType {
    var featureSupport: ServerFeatureSupport {
        switch self {
        case .jellyfin: return JellyfinFeatureSupport()
        case .emby: return EmbyFeatureSupport()
        }
    }

    func supports(_ feature: ServerFeature) -> Bool {
        featureSupport.isSupported(feature)
    }
}
