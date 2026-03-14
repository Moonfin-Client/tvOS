import SwiftUI

struct SettingsParentalControlsScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme

    @State private var availableRatings: [String] = []
    @State private var blockedRatings: Set<String> = []
    @State private var isLoading = true

    private var repo: ParentalControlsRepository { container.parentalControlsRepository }

    var body: some View {
        SettingsScreenLayout(title: "Parental Controls") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceLg)
            } else if availableRatings.isEmpty {
                Text("No ratings found on your server")
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceLg)
            } else {
                ForEach(availableRatings, id: \.self) { rating in
                    SettingsToggleButton(
                        icon: "eye.slash",
                        heading: rating,
                        isOn: ratingBinding(for: rating)
                    )
                }
            }
        }
        .task { await loadRatings() }
    }

    private func loadRatings() async {
        blockedRatings = repo.getBlockedRatings()
        availableRatings = await repo.getAvailableRatings()
        isLoading = false
    }

    private func ratingBinding(for rating: String) -> Binding<Bool> {
        Binding(
            get: { blockedRatings.contains(rating) },
            set: { blocked in
                if blocked {
                    blockedRatings.insert(rating)
                } else {
                    blockedRatings.remove(rating)
                }
                repo.setBlockedRatings(blockedRatings)
            }
        )
    }
}
