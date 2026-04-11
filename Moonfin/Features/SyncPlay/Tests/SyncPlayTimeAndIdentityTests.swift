import XCTest
@testable import Moonfin

final class SyncPlayTimeAndIdentityTests: XCTestCase {

    func testTicksMsRoundTrip() {
        let ms: Int64 = 12_345
        let ticks = SyncPlayUtils.msToTicks(ms)
        XCTAssertEqual(ticks, 123_450_000)
        XCTAssertEqual(SyncPlayUtils.ticksToMs(ticks), ms)
    }

    func testParseISODateSupportsFractionalAndNonFractional() {
        let fractional = "2026-04-11T20:18:00.1000000Z"
        let plain = "2026-04-11T20:18:00Z"

        let f = SyncPlayUtils.parseISOToMs(fractional)
        let p = SyncPlayUtils.parseISOToMs(plain)

        XCTAssertEqual(f - p, 100)
    }

    func testCommandIdentityUsesStableCompositeFields() throws {
        let a = try decodeCommand(
            groupId: "g1",
            command: "Unpause",
            when: "2026-04-11T20:18:00.0000000Z",
            playlistItemId: "p1",
            emittedAt: "2026-04-11T20:17:59.5000000Z"
        )
        let b = try decodeCommand(
            groupId: "g1",
            command: "Unpause",
            when: "2026-04-11T20:18:00.0000000Z",
            playlistItemId: "p1",
            emittedAt: "2026-04-11T20:17:59.6000000Z"
        )

        let aKey = SyncPlayCommandIdentity.dedupeKey(for: a)
        let bKey = SyncPlayCommandIdentity.dedupeKey(for: b)

        XCTAssertNotEqual(aKey, bKey)
    }

    func testCommandIdentityDiffersByPlaylistItem() throws {
        let a = try decodeCommand(
            groupId: "g1",
            command: "Seek",
            when: "2026-04-11T20:18:00.0000000Z",
            playlistItemId: "p1",
            emittedAt: "2026-04-11T20:17:59.5000000Z"
        )
        let b = try decodeCommand(
            groupId: "g1",
            command: "Seek",
            when: "2026-04-11T20:18:00.0000000Z",
            playlistItemId: "p2",
            emittedAt: "2026-04-11T20:17:59.5000000Z"
        )

        XCTAssertNotEqual(
            SyncPlayCommandIdentity.dedupeKey(for: a),
            SyncPlayCommandIdentity.dedupeKey(for: b)
        )
    }

    private func decodeCommand(
        groupId: String,
        command: String,
        when: String,
        playlistItemId: String,
        emittedAt: String
    ) throws -> SyncPlayCommand {
        let json = """
        {
          "GroupId": "\(groupId)",
          "Command": "\(command)",
          "PositionTicks": 10000000,
          "When": "\(when)",
          "PlaylistItemId": "\(playlistItemId)",
          "EmittedAt": "\(emittedAt)"
        }
        """
        return try JSONDecoder().decode(SyncPlayCommand.self, from: Data(json.utf8))
    }
}
