import XCTest
@testable import Puzzle

@MainActor
final class StorageTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "PuzzleTests.storage"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testScoresRankByTimeThenMovesAndKeepTen() {
        let scores = ScoreRepository(defaults: defaults)
        XCTAssertTrue(scores.record(Score(gridSize: 4, timeMs: 5_000, moves: 40, playedAt: 1)))
        XCTAssertTrue(scores.record(Score(gridSize: 4, timeMs: 5_000, moves: 30, playedAt: 2)))
        XCTAssertTrue(scores.record(Score(gridSize: 4, timeMs: 4_000, moves: 90, playedAt: 3)))
        XCTAssertEqual(scores.topTen(4).map(\.playedAt), [3, 2, 1])
        for i in 0..<7 { _ = scores.record(Score(gridSize: 4, timeMs: 1_000, moves: 10, playedAt: Int64(10 + i))) }
        XCTAssertEqual(scores.topTen(4).count, 10)
        // A tie with the 10th row ranks after it, so it does not make the board.
        XCTAssertFalse(scores.record(Score(gridSize: 4, timeMs: 5_000, moves: 40, playedAt: 99)))
        XCTAssertTrue(scores.topTen(5).isEmpty)
    }

    func testSettingsClampAndTrim() {
        let settings = SettingsRepository(defaults: defaults)
        XCTAssertEqual(settings.appearance, .system)
        settings.setGridSize(42)
        XCTAssertEqual(settings.gridSize, PuzzleState.maxSize)
        settings.setPlayerName("   A very long player name that goes on   ")
        XCTAssertEqual(settings.playerName?.count, 24)
        settings.setAppearance(.dark)
        XCTAssertEqual(SettingsRepository(defaults: defaults).appearance, .dark)
    }

    func testDecodesDataStoreProtobuf() {
        let json = #"[{"gridSize":4,"timeMs":1234,"moves":56,"playedAt":1700000000000}]"#
        let bytes = entry("gridSize", value: field(3, varint: 6))
            + entry("appearance", value: field(5, bytes: Array("DARK".utf8)))
            + entry("scores_4", value: field(5, bytes: Array(json.utf8)))
            + entry("big", value: field(4, varint: UInt64(bitPattern: -2)))
        let decoded = LegacyPreferencesImport.decode(Data(bytes))
        XCTAssertEqual(decoded["gridSize"], .int(6))
        XCTAssertEqual(decoded["appearance"], .string("DARK"))
        XCTAssertEqual(decoded["scores_4"], .string(json))
        XCTAssertEqual(decoded["big"], .int(-2))
        XCTAssertTrue(LegacyPreferencesImport.decode(Data([0xFF, 0xFF])).isEmpty)
    }

    // MARK: - Tiny protobuf writer

    private func varint(_ value: UInt64) -> [UInt8] {
        var v = value, out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    private func field(_ number: Int, varint value: UInt64) -> [UInt8] { varint(UInt64(number << 3)) + varint(value) }
    private func field(_ number: Int, bytes: [UInt8]) -> [UInt8] { varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes }
    private func entry(_ key: String, value: [UInt8]) -> [UInt8] {
        field(1, bytes: field(1, bytes: Array(key.utf8)) + field(2, bytes: value))
    }
}
