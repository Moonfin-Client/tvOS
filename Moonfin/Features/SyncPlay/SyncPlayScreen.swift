import SwiftUI

struct SyncPlayScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @State private var groupName = ""

    private var syncPlayManager: SyncPlayManager { container.syncPlayManager }

    var body: some View {
        SettingsScreenLayout(title: Strings.syncPlay) {
            if !syncPlayManager.syncPlayConfigured {
                unavailableSection(title: Strings.syncPlayDisabledTitle, message: Strings.syncPlayDisabledMessage)
            } else if !syncPlayManager.syncPlayEnabled {
                unavailableSection(title: Strings.syncPlayServerUnsupportedTitle, message: Strings.syncPlayServerUnsupportedMessage)
            } else if syncPlayManager.state.enabled {
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
            if syncPlayManager.syncPlayEnabled && !syncPlayManager.state.enabled {
                await syncPlayManager.fetchGroups()
            }
        }
    }

    private func unavailableSection(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Text(title)
                .font(.bodySm)
                .bold()
                .foregroundColor(theme.colorScheme.listHeadline)
                .padding(.horizontal, SpaceTokens.spaceMd)
            Text(message)
                .font(.caption)
                .foregroundColor(theme.colorScheme.listCaption)
                .padding(.horizontal, SpaceTokens.spaceMd)
        }
    }

    private var activeGroupSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(theme.accent)
                Text(Strings.syncPlayInGroup)
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.listHeadline)
                Spacer()
                Text(syncPlayManager.state.groupState.rawValue)
                    .font(.caption)
                    .foregroundColor(theme.colorScheme.listCaption)
            }
            .padding(.horizontal, SpaceTokens.spaceMd)

            if let displayName = syncPlayManager.state.groupName ?? syncPlayManager.state.groupId {
                Text(displayName)
                    .font(.caption)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            }

            if !syncPlayManager.state.participants.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.syncPlayParticipants)
                        .font(.caption)
                        .foregroundColor(theme.colorScheme.listCaption)
                    Text(syncPlayManager.state.participants.joined(separator: " • "))
                        .font(.caption)
                        .foregroundColor(theme.colorScheme.listHeadline)
                        .lineLimit(2)
                }
                .padding(.horizontal, SpaceTokens.spaceMd)
            }

            groupOptionsSection
            groupQueueSection

            Button {
                Task { await syncPlayManager.leaveGroup() }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text(Strings.syncPlayLeaveGroup)
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

    private var groupOptionsSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Text(Strings.syncPlayGroupOptions)
                .font(.bodySm)
                .bold()
                .foregroundColor(theme.colorScheme.listCaption)
                .padding(.horizontal, SpaceTokens.spaceMd)

            HStack(spacing: SpaceTokens.spaceSm) {
                Button {
                    syncPlayManager.cycleRepeatMode()
                } label: {
                    Text(Strings.syncPlayRepeatValue(repeatLabel))
                        .font(.caption)
                }
                .buttonStyle(CleanButtonStyle())

                Button {
                    syncPlayManager.toggleShuffleMode()
                } label: {
                    Text(Strings.syncPlayShuffleValue(shuffleLabel))
                        .font(.caption)
                }
                .buttonStyle(CleanButtonStyle())
            }
            .padding(.horizontal, SpaceTokens.spaceMd)

            SettingsToggleButton(
                icon: "hourglass",
                heading: Strings.syncPlayIgnoreWait,
                caption: Strings.syncPlayIgnoreWaitDescription,
                isOn: Binding(
                    get: { syncPlayManager.ignoreWaitEnabled },
                    set: { syncPlayManager.requestSetIgnoreWait($0) }
                )
            )

            Button {
                Task { await syncPlayManager.syncCurrentPlaybackQueueToGroup() }
            } label: {
                HStack {
                    Image(systemName: "rectangle.stack.badge.play")
                    Text(Strings.syncPlaySyncCurrentQueue)
                        .font(.bodyMd)
                    Spacer()
                }
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.vertical, SpaceTokens.spaceSm)
            }
            .buttonStyle(CleanButtonStyle())
        }
    }

    private var groupQueueSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            HStack {
                Text(Strings.syncPlayGroupQueue)
                    .font(.bodySm)
                    .bold()
                    .foregroundColor(theme.colorScheme.listCaption)
                Spacer()
                Button {
                    syncPlayManager.requestQueueCurrentPlaybackItem(mode: .queue)
                } label: {
                    Text(Strings.syncPlayQueueCurrent)
                        .font(.caption)
                }
                .buttonStyle(CleanButtonStyle())

                Button {
                    syncPlayManager.requestQueueCurrentPlaybackItem(mode: .queueNext)
                } label: {
                    Text(Strings.syncPlayQueueNext)
                        .font(.caption)
                }
                .buttonStyle(CleanButtonStyle())
            }
            .padding(.horizontal, SpaceTokens.spaceMd)

            if syncPlayManager.state.queue.isEmpty {
                Text(Strings.syncPlayQueueEmpty)
                    .font(.caption)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            } else {
                ForEach(Array(syncPlayManager.state.queue.enumerated()), id: \.element.playlistItemId) { index, item in
                    HStack(spacing: SpaceTokens.spaceSm) {
                        if index == syncPlayManager.state.currentItemIndex {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(theme.accent)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(theme.colorScheme.listCaption)
                        }

                        Text(item.itemId)
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundColor(theme.colorScheme.listHeadline)

                        Spacer()

                        Button(Strings.syncPlaySet) {
                            syncPlayManager.requestSetCurrentItem(playlistItemId: item.playlistItemId)
                        }
                        .buttonStyle(CleanButtonStyle())

                        Button(Strings.syncPlayUp) {
                            syncPlayManager.requestMoveQueueItem(playlistItemId: item.playlistItemId, to: max(0, index - 1))
                        }
                        .buttonStyle(CleanButtonStyle())
                        .disabled(index == 0)

                        Button(Strings.syncPlayDown) {
                            syncPlayManager.requestMoveQueueItem(playlistItemId: item.playlistItemId, to: index + 1)
                        }
                        .buttonStyle(CleanButtonStyle())
                        .disabled(index == syncPlayManager.state.queue.count - 1)

                        Button(Strings.remove) {
                            syncPlayManager.requestRemoveFromQueue(playlistItemId: item.playlistItemId)
                        }
                        .buttonStyle(CleanButtonStyle())
                    }
                    .padding(.horizontal, SpaceTokens.spaceMd)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var repeatLabel: String {
        switch syncPlayManager.state.repeatMode {
        case .repeatNone: return Strings.syncPlayRepeatOff
        case .repeatOne: return Strings.syncPlayRepeatOne
        case .repeatAll: return Strings.syncPlayRepeatAll
        }
    }

    private var shuffleLabel: String {
        syncPlayManager.state.shuffleMode == .shuffle ? Strings.on : Strings.syncPlayRepeatOff
    }

    private var createGroupSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Text(Strings.syncPlayCreateGroup)
                .font(.bodySm)
                .bold()
                .foregroundColor(theme.colorScheme.listCaption)
                .padding(.horizontal, SpaceTokens.spaceMd)

            Button {
                let name = groupName.isEmpty ? Strings.syncPlayDefaultGroupName : groupName
                Task { await syncPlayManager.createGroup(name: name) }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(Strings.syncPlayNewGroup)
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
                Text(Strings.syncPlayAvailableGroups)
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
                Text(Strings.syncPlayNoGroups)
                    .font(.caption)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            }

            ForEach(syncPlayManager.availableGroups, id: \.groupId) { group in
                Button {
                    Task { await syncPlayManager.joinGroup(group.groupId, withCurrentQueueSnapshot: true) }
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
                    Text(Strings.syncPlayRefresh)
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
                Text(Strings.syncPlayParticipantsLine(group.participants.count, group.participants.count == 1 ? Strings.syncPlayParticipantSingular : Strings.syncPlayParticipantPlural, group.state))
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
