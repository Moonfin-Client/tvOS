import SwiftUI

struct SettingsMaxBitrateScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var current: Int { container.userPreferences[UserPreferences.maxBitrate] }

    private let options: [(Int, String)] = [
        (0, "Auto"),
        (120_000_000, "120 Mbps — 4K High"),
        (80_000_000, "80 Mbps — 4K"),
        (60_000_000, "60 Mbps — 4K"),
        (40_000_000, "40 Mbps — 1080p High"),
        (20_000_000, "20 Mbps — 1080p"),
        (15_000_000, "15 Mbps — 1080p"),
        (10_000_000, "10 Mbps — 720p"),
        (8_000_000, "8 Mbps — 720p"),
        (6_000_000, "6 Mbps"),
        (4_000_000, "4 Mbps"),
        (3_000_000, "3 Mbps"),
        (2_000_000, "2 Mbps — 480p"),
        (1_500_000, "1.5 Mbps"),
        (1_000_000, "1 Mbps"),
        (700_000, "0.7 Mbps — 360p"),
        (420_000, "0.42 Mbps"),
    ]

    var body: some View {
        SettingsScreenLayout(title: "Max Bitrate") {
            ForEach(options, id: \.0) { value, label in
                Button {
                    container.userPreferences[UserPreferences.maxBitrate] = value
                    settingsRouter.goBack()
                } label: {
                    RadioOptionContent(label: label, isSelected: current == value)
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
    }
}
