import Foundation

enum DynamicHomeSectionSource {
    case hss
    case collections
    case genres
    case kefinTweaks
}

struct DynamicHomeSectionQuery {
    let source: DynamicHomeSectionSource
    let sectionType: String
    let additionalData: String?
}

enum RowQueryType {
    case items(GetItemsRequest)
    case resume(GetResumeItemsRequest)
    case nextUp(GetNextUpRequest)
    case mergedContinueWatching(resume: GetResumeItemsRequest, nextUp: GetNextUpRequest)
    case latestMedia(GetLatestMediaRequest)
    case similar(itemId: String, limit: Int?)
    case seasons(seriesId: String, userId: String)
    case episodes(seriesId: String, seasonId: String, userId: String)
    case userViews(userId: String)
    case liveTvChannels
    case liveTvOnNow
    case liveTvComingUp
    case liveTvRecordings
    case pluginDynamic(DynamicHomeSectionQuery)
    case staticItems([ServerItem])
}
