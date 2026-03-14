import SwiftUI

struct SettingsSeerrRowsScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme

    @State private var rows: [SeerrRowConfig] = []

    private var repo: SeerrRepositoryProtocol { container.seerrRepository }

    var body: some View {
        SettingsScreenLayout(title: "Discover Rows") {
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
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Defaults")
                }
                .font(.bodyMd)
                .foregroundColor(theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, SpaceTokens.spaceMd)
            }
            .buttonStyle(CleanButtonStyle())
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
        HStack(spacing: SpaceTokens.spaceSm) {
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isFirst ? theme.colorScheme.listCaption.opacity(0.3) : theme.accent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(CleanButtonStyle())
            .disabled(isFirst)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isLast ? theme.colorScheme.listCaption.opacity(0.3) : theme.accent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(CleanButtonStyle())
            .disabled(isLast)

            Image(systemName: iconForRowType(row.type))
                .font(.system(size: 16))
                .foregroundColor(row.enabled ? theme.accent : theme.colorScheme.listCaption)
                .frame(width: 24)

            Text(row.type.displayName)
                .font(.bodyMd)
                .foregroundColor(row.enabled ? theme.colorScheme.onBackground : theme.colorScheme.listCaption)

            Spacer()

            Button(action: onToggle) {
                Image(systemName: row.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(row.enabled ? theme.accent : theme.colorScheme.listCaption)
            }
            .buttonStyle(CleanButtonStyle())
        }
        .padding(.vertical, SpaceTokens.space2xs)
    }

    private func iconForRowType(_ type: SeerrRowType) -> String {
        switch type {
        case .recentRequests: return "clock.arrow.circlepath"
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
