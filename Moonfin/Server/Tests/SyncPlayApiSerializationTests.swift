import Foundation
import XCTest

final class SyncPlayApiSerializationTests: XCTestCase {
    private let encoder = JSONEncoder()

    func testSetPlaylistItemRequestEncoding() throws {
        let body = SyncPlaySetPlaylistItemRequest(playlistItemId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let json = try encodeToObject(body)

        XCTAssertEqual(json["PlaylistItemId"] as? String, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    }

    func testRemoveFromPlaylistRequestEncoding() throws {
        let body = SyncPlayRemoveFromPlaylistRequest(
            playlistItemIds: ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"],
            clearPlaylist: false,
            clearPlayingItem: true
        )
        let json = try encodeToObject(body)

        XCTAssertEqual(json["PlaylistItemIds"] as? [String], ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"])
        XCTAssertEqual(json["ClearPlaylist"] as? Bool, false)
        XCTAssertEqual(json["ClearPlayingItem"] as? Bool, true)
    }

    func testMovePlaylistItemRequestEncoding() throws {
        let body = SyncPlayMovePlaylistItemRequest(
            playlistItemId: "ffffffff-1111-2222-3333-444444444444",
            newIndex: 2
        )
        let json = try encodeToObject(body)

        XCTAssertEqual(json["PlaylistItemId"] as? String, "ffffffff-1111-2222-3333-444444444444")
        XCTAssertEqual(json["NewIndex"] as? Int, 2)
    }

    func testQueueRequestEncoding() throws {
        let body = SyncPlayQueueRequest(itemIds: ["11111111-2222-3333-4444-555555555555"], mode: .queueNext)
        let json = try encodeToObject(body)

        XCTAssertEqual(json["ItemIds"] as? [String], ["11111111-2222-3333-4444-555555555555"])
        XCTAssertEqual(json["Mode"] as? String, "QueueNext")
    }

    func testRepeatAndShuffleRequestEncoding() throws {
        let repeatBody = SyncPlaySetRepeatModeRequest(mode: .repeatAll)
        let shuffleBody = SyncPlaySetShuffleModeRequest(mode: .shuffle)

        let repeatJson = try encodeToObject(repeatBody)
        let shuffleJson = try encodeToObject(shuffleBody)

        XCTAssertEqual(repeatJson["Mode"] as? String, "RepeatAll")
        XCTAssertEqual(shuffleJson["Mode"] as? String, "Shuffle")
    }

    func testIgnoreWaitRequestEncoding() throws {
        let body = SyncPlaySetIgnoreWaitRequest(ignoreWait: true)
        let json = try encodeToObject(body)

        XCTAssertEqual(json["IgnoreWait"] as? Bool, true)
    }

    private func encodeToObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        return try XCTUnwrap(json as? [String: Any])
    }
}
