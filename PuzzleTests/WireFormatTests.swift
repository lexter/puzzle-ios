import XCTest
@testable import Puzzle

/// The wire format must stay byte-compatible with the Android app (kotlinx.serialization JSON).
final class WireFormatTests: XCTestCase {
    private let all: [MatchMessage] = [
        .hello(protocolVersion: protocolVersion, playerName: "Mia", platform: "android"),
        .config(MatchConfig(grid: 5, seed: -42, mode: .free, customImage: true, imageBytes: 1234)),
        .ready, .imageFailed, .start(countdownMs: MatchMessage.countdownMs),
        .progress(tiles: [1, 0, 2, 3], moves: 7, tilesInPlace: 1),
        .solved(elapsedMs: 61_000, moves: 88),
        .result(winnerIsHost: false, winnerTimeMs: 61_000),
        .rematch, .leave, .ping,
    ]

    func testEveryMessageRoundTrips() throws {
        for message in all {
            let decoded = try Framing.Decoder().feed(MatchCodec.encode(.control(message)))
            XCTAssertEqual(decoded.count, 1)
            XCTAssertEqual(MatchCodec.fromRaw(decoded[0]), .control(message))
        }
    }

    func testDecodesKotlinJson() {
        func decode(_ json: String) -> Frame? { MatchCodec.fromRaw(RawFrame(kind: RawFrame.kindControl, payload: Data(json.utf8))) }
        XCTAssertEqual(decode(#"{"type":"hello","protocolVersion":1,"playerName":"Mia","platform":"android"}"#),
                       .control(.hello(protocolVersion: 1, playerName: "Mia", platform: "android")))
        XCTAssertEqual(decode(#"{"type":"config","grid":6,"seed":9007199254740993,"mode":"TIME_BASED","customImage":false,"imageBytes":0}"#),
                       .control(.config(MatchConfig(grid: 6, seed: 9_007_199_254_740_993, mode: .timeBased, customImage: false, imageBytes: 0))))
        XCTAssertEqual(decode(#"{"type":"config","grid":6,"seed":-9223372036854775808,"mode":"FREE","customImage":true,"imageBytes":5}"#),
                       .control(.config(MatchConfig(grid: 6, seed: .min, mode: .free, customImage: true, imageBytes: 5))))
        XCTAssertEqual(decode(#"{"type":"start"}"#), .control(.start(countdownMs: 3_000)))
        XCTAssertEqual(decode(#"{"type":"ready"}"#), .control(.ready))
        XCTAssertEqual(decode(#"{"moves":3,"type":"progress","tiles":[0,1],"tilesInPlace":1,"extra":true}"#),
                       .control(.progress(tiles: [0, 1], moves: 3, tilesInPlace: 1)))
    }

    func testEncodesKotlinShape() throws {
        let raw = try MatchCodec.toRaw(.control(.config(MatchConfig(grid: 4, seed: .max, mode: .timeBased, customImage: false, imageBytes: 0))))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw.payload) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "config")
        XCTAssertEqual(object["mode"] as? String, "TIME_BASED")
        XCTAssertTrue(String(decoding: raw.payload, as: UTF8.self).contains("\"seed\":9223372036854775807"))
        let ready = try MatchCodec.toRaw(.control(.ready))
        XCTAssertEqual(String(decoding: ready.payload, as: UTF8.self), #"{"type":"ready"}"#)
    }

    func testUnknownIsIgnored() {
        XCTAssertNil(MatchCodec.fromRaw(RawFrame(kind: RawFrame.kindControl, payload: Data(#"{"type":"emoji","value":"wave"}"#.utf8))))
        XCTAssertNil(MatchCodec.fromRaw(RawFrame(kind: 9, payload: Data([1, 2, 3]))))
    }

    func testFramingAcrossChunks() throws {
        let image = Data((0..<1000).map { UInt8($0 % 256) })
        let bytes = try MatchCodec.encode(.control(.ping)) + MatchCodec.encode(.image(image))
        let decoder = Framing.Decoder()
        var frames: [RawFrame] = []
        for start in stride(from: 0, to: bytes.count, by: 7) {
            frames += try decoder.feed(bytes.subdata(in: start..<min(start + 7, bytes.count)))
        }
        XCTAssertEqual(frames.map(MatchCodec.fromRaw), [.control(.ping), .image(image)])
        XCTAssertEqual(Array(try Framing.encode(RawFrame(kind: 1, payload: Data([9]))).prefix(5)), [0, 0, 0, 2, 1])
    }

    func testOversizedFrameRejected() {
        XCTAssertThrowsError(try Framing.Decoder().feed(Data([0x7F, 0, 0, 0, 0])))
    }
}
