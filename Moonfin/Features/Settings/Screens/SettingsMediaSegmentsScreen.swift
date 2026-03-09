import SwiftUI

struct SettingsMediaSegmentsScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var actionMap: [MediaSegmentType: MediaSegmentAction] {
        MediaSegmentRepositoryImpl.parseActionsString(
            container.userPreferences[UserPreferences.mediaSegmentActions]
        )
    }

    var body: some View {
        SettingsScreenLayout(title: "Media Segments") {
            ForEach(MediaSegmentType.supported, id: \.self) { type in
                let action = actionMap[type] ?? .nothing
                SettingsListButton(
                    icon: iconForType(type),
                    heading: type.displayName,
                    trailingText: action.displayName,
                    action: {
                        settingsRouter.navigate(to: .playbackMediaSegment(segmentType: type.rawValue))
                    }
                )
            }
        }
    }

    private func iconForType(_ type: MediaSegmentType) -> String {
        switch type {
        case .intro: return "forward.end.alt"
        case .outro: return "backward.end.alt"
        case .preview: return "eye"
        case .recap: return "arrow.counterclockwise"
        case .commercial: return "tv"
        case .unknown: return "questionmark.circle"
        }
    }
}
