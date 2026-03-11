import SwiftUI

struct SyncPlayScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @State private var groupName = ""

    private var syncPlayManager: SyncPlayManager { container.syncPlayManager }

    var body: some View {
        SettingsScreenLayout(title: "SyncPlay") {
            if syncPlayManager.state.enabled {
                activeGroupSection
            } else {
                createGroupSection
                availableGroupsSection
            }

            if let error = syncPlayManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            }
        }
        .task {
            if !syncPlayManager.state.enabled {
                await syncPlayManager.fetchGroups()
            }
        }
    }

    private var activeGroupSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(theme.accent)
                Text("In Group")
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.listHeadline)
                Spacer()
                Text(syncPlayManager.state.groupState.rawValue)
                    .font(.caption)
                    .foregroundColor(theme.colorScheme.listCaption)
            }
            .padding(.horizontal, SpaceTokens.spaceMd)

            if let info = syncPlayManager.state.groupInfo {
                Text(info.groupName ?? info.groupId)
                    .font(.caption)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            }

            Button {
                Task { await syncPlayManager.leaveGroup() }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Leave Group")
                        .font(.bodyMd)
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.vertical, SpaceTokens.spaceSm)
            }
            .buttonStyle(CleanButtonStyle())
        }
    }

    private var createGroupSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Text("Create Group")
                .font(.bodySm)
                .bold()
                .foregroundColor(theme.colorScheme.listCaption)
                .padding(.horizontal, SpaceTokens.spaceMd)

            Button {
                let name = groupName.isEmpty ? "SyncPlay Group" : groupName
                Task { await syncPlayManager.createGroup(name: name) }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Group")
                        .font(.bodyMd)
                    Spacer()
                }
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.vertical, SpaceTokens.spaceSm)
            }
            .buttonStyle(CleanButtonStyle())
            .disabled(syncPlayManager.isLoading)
        }
    }

    private var availableGroupsSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            HStack {
                Text("Available Groups")
                    .font(.bodySm)
                    .bold()
                    .foregroundColor(theme.colorScheme.listCaption)
                Spacer()
                if syncPlayManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, SpaceTokens.spaceMd)

            if syncPlayManager.availableGroups.isEmpty && !syncPlayManager.isLoading {
                Text("No groups found")
                    .font(.caption)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            }

            ForEach(syncPlayManager.availableGroups, id: \.groupId) { group in
                Button {
                    Task { await syncPlayManager.joinGroup(group.groupId) }
                } label: {
                    SyncPlayGroupRow(group: group)
                }
                .buttonStyle(CleanButtonStyle())
                .disabled(syncPlayManager.isLoading)
            }

            Button {
                Task { await syncPlayManager.fetchGroups() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                        .font(.bodyMd)
                    Spacer()
                }
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.vertical, SpaceTokens.spaceSm)
            }
            .buttonStyle(CleanButtonStyle())
            .disabled(syncPlayManager.isLoading)
        }
    }
}

private struct SyncPlayGroupRow: View {
    let group: SyncPlayGroupListItem
    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.groupName)
                    .font(.bodyMd)
                    .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)
                Text("\(group.participants.count) participant\(group.participants.count == 1 ? "" : "s") · \(group.state)")
                    .font(.caption)
                    .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(theme.colorScheme.listCaption)
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
    }
}
