import XCTest
@testable import Moonfin

final class SyncPlayStateReducerTests: XCTestCase {

    // MARK: - groupJoined

    func testGroupJoinedPopulatesState() {
        var state = SyncPlayState()
        let info = SyncPlayGroupInfo(
            groupId: "group-1",
            groupName: "Movie Night",
            state: .waiting,
            participants: ["alice", "bob"],
            lastUpdatedAt: "2026-04-11T20:14:00.0000000Z"
        )

        applyGroupJoined(info: info, to: &state)

        XCTAssertTrue(state.enabled)
        XCTAssertEqual(state.groupId, "group-1")
        XCTAssertEqual(state.groupName, "Movie Night")
        XCTAssertEqual(state.participants, ["alice", "bob"])
        XCTAssertEqual(state.groupState, .waiting)
        XCTAssertEqual(state.lastUpdateAt, "2026-04-11T20:14:00.0000000Z")
    }

    func testGroupJoinedWithNilStateDefaultsToIdle() {
        var state = SyncPlayState()
        let info = SyncPlayGroupInfo(
            groupId: "group-1",
            groupName: nil,
            state: nil,
            participants: [],
            lastUpdatedAt: nil
        )

        applyGroupJoined(info: info, to: &state)

        XCTAssertEqual(state.groupState, .idle)
    }

    // MARK: - groupLeft / errors

    func testGroupLeftResetsState() {
        var state = makeActiveState()

        applyReset(to: &state)

        XCTAssertFalse(state.enabled)
        XCTAssertNil(state.groupId)
        XCTAssertTrue(state.participants.isEmpty)
        XCTAssertTrue(state.queue.isEmpty)
        XCTAssertNil(state.currentPlaylistItemId)
    }

    // MARK: - stateUpdate

    func testStateUpdateChangesGroupState() {
        var state = makeActiveState()
        state.groupState = .waiting

        applyStateUpdate(newState: .playing, to: &state)

        XCTAssertEqual(state.groupState, .playing)
    }

    // MARK: - playQueue

    func testPlayQueueUpdateSetsQueueAndCurrentItem() {
        var state = makeActiveState()
        let items = [
            SyncPlayQueueItem(itemId: "item-a", playlistItemId: "pl-a"),
            SyncPlayQueueItem(itemId: "item-b", playlistItemId: "pl-b")
        ]
        let queueUpdate = SyncPlayPlayQueueUpdate(
            reason: .setCurrentItem,
            lastUpdate: "2026-04-11T20:18:00.0000000Z",
            playlist: items,
            playingItemIndex: 1,
            startPositionTicks: 0,
            isPlaying: true,
            shuffleMode: .sorted,
            repeatMode: .repeatNone
        )

        applyQueueUpdate(queueUpdate, to: &state)

        XCTAssertEqual(state.queue.count, 2)
        XCTAssertEqual(state.currentItemIndex, 1)
        XCTAssertEqual(state.currentPlaylistItemId, "pl-b")
        XCTAssertEqual(state.repeatMode, .repeatNone)
        XCTAssertEqual(state.shuffleMode, .sorted)
        XCTAssertEqual(state.lastUpdateAt, "2026-04-11T20:18:00.0000000Z")
    }

    func testPlayQueueOutOfBoundsClearsCurrentItemId() {
        var state = makeActiveState()
        let queueUpdate = SyncPlayPlayQueueUpdate(
            reason: .newPlaylist,
            lastUpdate: "2026-04-11T20:00:00.0000000Z",
            playlist: [],
            playingItemIndex: 0,
            startPositionTicks: 0,
            isPlaying: false,
            shuffleMode: .sorted,
            repeatMode: .repeatNone
        )

        applyQueueUpdate(queueUpdate, to: &state)

        XCTAssertNil(state.currentPlaylistItemId)
    }

    func testPlayQueueRepeatAndShuffleUpdated() {
        var state = makeActiveState()
        let queueUpdate = SyncPlayPlayQueueUpdate(
            reason: .shuffleMode,
            lastUpdate: "2026-04-11T20:00:00.0000000Z",
            playlist: [SyncPlayQueueItem(itemId: "i", playlistItemId: "p")],
            playingItemIndex: 0,
            startPositionTicks: 0,
            isPlaying: true,
            shuffleMode: .shuffle,
            repeatMode: .repeatAll
        )

        applyQueueUpdate(queueUpdate, to: &state)

        XCTAssertEqual(state.repeatMode, .repeatAll)
        XCTAssertEqual(state.shuffleMode, .shuffle)
    }

    // MARK: - userJoined / userLeft

    func testUserJoinedAddsParticipant() {
        var state = makeActiveState()
        state.participants = ["alice"]

        applyUserJoined("charlie", to: &state)

        XCTAssertEqual(state.participants, ["alice", "charlie"])
    }

    func testUserJoinedDoesNotAddDuplicate() {
        var state = makeActiveState()
        state.participants = ["alice"]

        applyUserJoined("alice", to: &state)

        XCTAssertEqual(state.participants.count, 1)
    }

    func testUserLeftRemovesParticipant() {
        var state = makeActiveState()
        state.participants = ["alice", "bob"]

        applyUserLeft("bob", to: &state)

        XCTAssertEqual(state.participants, ["alice"])
    }

    // MARK: - Decode fixtures

    func testGroupJoinedFixtureDecodes() throws {
        let json = """
        {
          "GroupId": "f0f0f0f0-1111-2222-3333-444444444444",
          "Type": "GroupJoined",
          "Data": {
            "GroupId": "f0f0f0f0-1111-2222-3333-444444444444",
            "GroupName": "Movie Night",
            "State": "Waiting",
            "Participants": ["alice", "bob"],
            "LastUpdatedAt": "2026-04-11T20:14:00.0000000Z"
          }
        }
        """
        let update = try JSONDecoder().decode(SyncPlayGroupUpdate.self, from: Data(json.utf8))
        XCTAssertEqual(update.type, .groupJoined)
        guard case .groupJoined(let info) = update.payload else {
            return XCTFail("Expected groupJoined payload")
        }
        XCTAssertEqual(info.groupName, "Movie Night")
        XCTAssertEqual(info.participants.count, 2)
    }

    func testPlayQueueFixtureDecodes() throws {
        let json = """
        {
          "GroupId": "f0f0f0f0-1111-2222-3333-444444444444",
          "Type": "PlayQueue",
          "Data": {
            "Reason": "SetCurrentItem",
            "LastUpdate": "2026-04-11T20:18:00.1000000Z",
            "Playlist": [
              {"ItemId": "11111111-2222-3333-4444-555555555555", "PlaylistItemId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"},
              {"ItemId": "66666666-7777-8888-9999-000000000000", "PlaylistItemId": "ffffffff-1111-2222-3333-444444444444"}
            ],
            "PlayingItemIndex": 0,
            "StartPositionTicks": 150000000,
            "IsPlaying": true,
            "ShuffleMode": "Sorted",
            "RepeatMode": "RepeatNone"
          }
        }
        """
        let update = try JSONDecoder().decode(SyncPlayGroupUpdate.self, from: Data(json.utf8))
        guard case .playQueue(let q) = update.payload else {
            return XCTFail("Expected playQueue payload")
        }
        XCTAssertEqual(q.playlist.count, 2)
        XCTAssertEqual(q.playlist[0].playlistItemId, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertEqual(q.playingItemIndex, 0)
        XCTAssertEqual(q.repeatMode, .repeatNone)
    }

    // MARK: - Helpers

    private func makeActiveState() -> SyncPlayState {
        var state = SyncPlayState()
        state.enabled = true
        state.groupId = "group-1"
        state.groupName = "Test Group"
        state.participants = ["alice"]
        state.groupState = .playing
        return state
    }

    private func applyGroupJoined(info: SyncPlayGroupInfo, to state: inout SyncPlayState) {
        state.enabled = true
        state.groupId = info.groupId
        state.groupName = info.groupName
        state.participants = info.participants
        state.lastUpdateAt = info.lastUpdatedAt
        if let s = info.state { state.groupState = s }
    }

    private func applyReset(to state: inout SyncPlayState) {
        state = SyncPlayState()
    }

    private func applyStateUpdate(newState: SyncPlayGroupState, to state: inout SyncPlayState) {
        state.groupState = newState
    }

    private func applyQueueUpdate(_ update: SyncPlayPlayQueueUpdate, to state: inout SyncPlayState) {
        state.queue = update.playlist
        state.currentItemIndex = update.playingItemIndex
        let idx = update.playingItemIndex
        state.currentPlaylistItemId = (idx >= 0 && idx < update.playlist.count)
            ? update.playlist[idx].playlistItemId
            : nil
        state.repeatMode = update.repeatMode
        state.shuffleMode = update.shuffleMode
        state.lastUpdateAt = update.lastUpdate
    }

    private func applyUserJoined(_ username: String, to state: inout SyncPlayState) {
        if !state.participants.contains(username) {
            state.participants.append(username)
        }
    }

    private func applyUserLeft(_ username: String, to state: inout SyncPlayState) {
        state.participants.removeAll { $0 == username }
    }
}
