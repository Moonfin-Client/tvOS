import SwiftUI

struct SettingsSeerrRowsScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme

    @State private var rows: [SeerrRowConfig] = []

    private var repo: SeerrRepositoryProtocol { container.seerrRepository }

    var body: some View {
        SettingsScreenLayout(title: "Discover Rows") {
            Text("Press left or right to rearrange")
                .font(.caption)
                .foregroundColor(theme.colorScheme.listCaption)
                .padding(.bottom, SpaceTokens.space2xs)

            ForEach(Array(rows.enumerated()), id: \.element.type.rawValue) { index, row in
                SeerrRowItem(
                    row: row,
                    isFirst: index == 0,
                    isLast: index == rows.count - 1,
                    onToggle: { toggleRow(at: index) },
                    onMoveUp: { moveRow(from: index, direction: -1) },
                    onMoveDown: { moveRow(from: index, direction: 1) }
                )
            }

            Button(action: resetToDefaults) {
                FocusAwareActionLabel(icon: "arrow.counterclockwise", text: "Reset to Defaults")
            }
            .buttonStyle(CleanButtonStyle())
            .padding(.top, SpaceTokens.spaceMd)
        }
        .onAppear { loadRows() }
    }

    private func loadRows() {
        let prefs = repo.getPreferences()
        var config = prefs?.rowsConfig ?? SeerrRowConfig.defaults()
        let existing = Set(config.map(\.type))
        for type in SeerrRowType.allCases where !existing.contains(type) {
            config.append(SeerrRowConfig(type: type, enabled: false, order: config.count))
        }
        rows = config.sorted { $0.order < $1.order }
    }

    private func saveRows() {
        let updated = rows.enumerated().map { index, row in
            SeerrRowConfig(type: row.type, enabled: row.enabled, order: index)
        }
        let prefs = repo.getPreferences()
        prefs?.rowsConfig = updated
    }

    private func toggleRow(at index: Int) {
        rows[index] = SeerrRowConfig(
            type: rows[index].type,
            enabled: !rows[index].enabled,
            order: rows[index].order
        )
        saveRows()
    }

    private func moveRow(from index: Int, direction: Int) {
        let target = index + direction
        guard target >= 0 && target < rows.count else { return }
        rows.swapAt(index, target)
        saveRows()
    }

    private func resetToDefaults() {
        rows = SeerrRowConfig.defaults()
        saveRows()
    }
}

private struct SeerrRowItem: View {
    let row: SeerrRowConfig
    let isFirst: Bool
    let isLast: Bool
    let onToggle: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: onToggle) {
            SettingsItemContent(
                icon: iconForRowType(row.type),
                heading: row.type.displayName,
                caption: nil
            ) { isFocused in
                HStack(spacing: SpaceTokens.spaceSm) {
                    if !isFirst {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
                    }
                    if !isLast {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
                    }
                    Image(systemName: row.enabled ? "checkmark.circle.fill" : "circle")
                        .font(.bodyLg)
                        .foregroundColor(row.enabled
                            ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                            : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
                }
            }
        }
        .buttonStyle(CleanButtonStyle())
        .onMoveCommand { direction in
            switch direction {
            case .left: onMoveUp()
            case .right: onMoveDown()
            default: break
            }
        }
    }

    private func iconForRowType(_ type: SeerrRowType) -> String {
        switch type {
        case .recentRequests: return "clock.arrow.circlepath"
        case .recentlyAdded: return "sparkles"
        case .trending: return "flame"
        case .popularMovies: return "film"
        case .movieGenres: return "theatermasks"
        case .upcomingMovies: return "calendar"
        case .studios: return "building.2"
        case .popularSeries: return "tv"
        case .seriesGenres: return "theatermasks.fill"
        case .upcomingSeries: return "calendar.badge.clock"
        case .networks: return "antenna.radiowaves.left.and.right"
        }
    }
}
