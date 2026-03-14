import SwiftUI
import Nuke

struct SettingsDeveloperScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme

    @State private var cacheSize: String = "Calculating..."
    @State private var showClearConfirmation = false
    @State private var cacheCleared = false

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Developer") {
            SettingsToggleButton(
                icon: "ladybug",
                heading: "Debug Logging",
                caption: "Enable verbose logging for troubleshooting",
                isOn: prefs.binding(for: UserPreferences.debuggingEnabled)
            )

            SettingsToggleButton(
                icon: "film.stack",
                heading: "TrickPlay",
                caption: "Show seek preview thumbnails during playback",
                isOn: prefs.binding(for: UserPreferences.trickPlayEnabled)
            )

            Button(action: { showClearConfirmation = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "trash.circle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear Image Cache")
                            .font(.bodyMd)
                        Text(cacheCleared ? "Cache cleared" : cacheSize)
                            .font(.captionSm)
                            .foregroundColor(theme.colorScheme.listCaption)
                    }
                    Spacer()
                }
                .foregroundColor(theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpaceTokens.spaceSm)
            }
            .buttonStyle(CleanButtonStyle())
            .alert("Clear Image Cache", isPresented: $showClearConfirmation) {
                Button("Clear", role: .destructive) { clearCache() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove all cached images. They will be re-downloaded as needed.")
            }
        }
        .onAppear { calculateCacheSize() }
    }

    private func calculateCacheSize() {
        Task.detached(priority: .utility) {
            var totalBytes: Int64 = 0

            if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
                totalBytes += Int64(dataCache.totalSize)
            }

            let formatted = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

            await MainActor.run {
                cacheSize = formatted
                cacheCleared = false
            }
        }
    }

    private func clearCache() {
        ImagePipeline.shared.cache.removeAll()
        cacheCleared = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            calculateCacheSize()
        }
    }
}
