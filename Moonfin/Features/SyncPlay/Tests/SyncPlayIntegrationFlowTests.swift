import XCTest
@testable import Moonfin

final class SyncPlayIntegrationFlowTests: XCTestCase {

    func testJoinQueueAndWaitingToPlayingFlow() throws {
        var state = SyncPlayState()

        let join = try decodeUpdate("""
        {
          "GroupId": "g1",
          "Type": "GroupJoined",
          "Data": {
            "GroupId": "g1",
            "GroupName": "Movie Night",
            "State": "Waiting",
            "Participants": ["alice", "bob"],
            "LastUpdatedAt": "2026-04-11T20:14:00.0000000Z"
          }
        }
        """)
        apply(update: join, to: &state)

        let queue = try decodeUpdate("""
        {
          "GroupId": "g1",
          "Type": "PlayQueue",
          "Data": {
            "Reason": "SetCurrentItem",
            "LastUpdate": "2026-04-11T20:18:00.1000000Z",
            "Playlist": [
              {"ItemId": "i1", "PlaylistItemId": "p1"},
              {"ItemId": "i2", "PlaylistItemId": "p2"}
            ],
            "PlayingItemIndex": 1,
            "StartPositionTicks": 0,
            "IsPlaying": true,
            "ShuffleMode": "Sorted",
            "RepeatMode": "RepeatNone"
          }
        }
        """)
        apply(update: queue, to: &state)

        let playing = try decodeUpdate("""
        {
          "GroupId": "g1",
          "Type": "StateUpdate",
          "Data": {
            "State": "Playing",
            "Reason": "Command"
          }
        }
        """)
        apply(update: playing, to: &state)

        XCTAssertTrue(state.enabled)
        XCTAssertEqual(state.groupId, "g1")
        XCTAssertEqual(state.groupState, .playing)
        XCTAssertEqual(state.currentPlaylistItemId, "p2")
        XCTAssertEqual(state.queue.count, 2)
    }

    func testWaitingToPausedFlow() throws {
        var state = SyncPlayState()

        let join = try decodeUpdate("""
        {
          "GroupId": "g1",
          "Type": "GroupJoined",
          "Data": {
            "GroupId": "g1",
            "GroupName": "Night",
            "State": "Waiting",
            "Participants": ["alice"],
            "LastUpdatedAt": "2026-04-11T20:14:00.0000000Z"
          }
        }
        """)
        apply(update: join, to: &state)

        let paused = try decodeUpdate("""
        {
          "GroupId": "g1",
          "Type": "StateUpdate",
          "Data": {
            "State": "Paused",
            "Reason": "Command"
          }
        }
        """)
        apply(update: paused, to: &state)

        XCTAssertEqual(state.groupState, .paused)
    }

    func testLeaveResetsState() throws {
        var state = SyncPlayState()
        state.enabled = true
        state.groupId = "g1"
        state.queue = [SyncPlayQueueItem(itemId: "i1", playlistItemId: "p1")]

        let left = try decodeUpdate("""
        {
          "GroupId": "g1",
          "Type": "GroupLeft",
          "Data": "g1"
        }
        """)
        apply(update: left, to: &state)

        XCTAssertFalse(state.enabled)
        XCTAssertNil(state.groupId)
        XCTAssertTrue(state.queue.isEmpty)
    }

    func testReconnectFallbackResolution() {
        let groups = [
            SyncPlayGroupListItem(groupId: "g1", groupName: "Main", state: "Playing", participants: ["a", "b"], lastUpdatedAt: "t"),
            SyncPlayGroupListItem(groupId: "g2", groupName: "Other", state: "Paused", participants: ["c"], lastUpdatedAt: "t2")
        ]

        let resolved = groups.first(where: { $0.groupId == "g1" })
        XCTAssertEqual(resolved?.groupName, "Main")
        XCTAssertEqual(resolved?.state, "Playing")
        XCTAssertEqual(resolved?.participants.count, 2)
    }

    private func decodeUpdate(_ json: String) throws -> SyncPlayGroupUpdate {
        try JSONDecoder().decode(SyncPlayGroupUpdate.self, from: Data(json.utf8))
    }

    private func apply(update: SyncPlayGroupUpdate, to state: inout SyncPlayState) {
        switch update.type {
        case .groupJoined:
            if case .groupJoined(let info) = update.payload {
                state.enabled = true
                state.groupId = info.groupId
                state.groupName = info.groupName
                state.participants = info.participants
                state.lastUpdateAt = info.lastUpdatedAt
                state.groupState = info.state ?? .idle
            }
        case .stateUpdate:
            if case .stateUpdate(let s) = update.payload {
                state.groupState = s.state
            }
        case .playQueue:
            if case .playQueue(let q) = update.payload {
                state.queue = q.playlist
                state.currentItemIndex = q.playingItemIndex
                let idx = q.playingItemIndex
                state.currentPlaylistItemId = (idx >= 0 && idx < q.playlist.count) ? q.playlist[idx].playlistItemId : nil
                state.repeatMode = q.repeatMode
                state.shuffleMode = q.shuffleMode
                state.lastUpdateAt = q.lastUpdate
            }
        case .groupLeft, .notInGroup, .groupDoesNotExist, .libraryAccessDenied:
            state = SyncPlayState()
        case .userJoined:
            if case .userJoined(let name) = update.payload, !state.participants.contains(name) {
                state.participants.append(name)
            }
        case .userLeft:
            if case .userLeft(let name) = update.payload {
                state.participants.removeAll { $0 == name }
            }
        }
    }
}
