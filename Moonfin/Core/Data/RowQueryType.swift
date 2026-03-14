import Foundation

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
    case staticItems([ServerItem])
}
