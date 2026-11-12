import Foundation

let protocolVersion = 1
let serviceType = "_slidepuzzle._tcp"

/// `imageBytes > 0` means a `Frame.image` with the host's photo follows.
struct MatchConfig: Equatable {
    let grid: Int
    let seed: Int64
    let mode: Mode
    let customImage: Bool
    let imageBytes: Int

    /// False for a config from a peer that would produce a board this app can't build.
    var isValid: Bool { (PuzzleState.minSize...PuzzleState.maxSize).contains(grid) }
}

/// Control messages. The JSON shape (a `type` discriminator plus fields) is the wire format
/// shared with the Android app, so names and field keys must not change.
enum MatchMessage: Equatable {
    static let countdownMs: Int64 = 3_000
    /// Longest countdown a guest will honour; a peer's `start` is clamped to `0...maxCountdownMs`.
    static let maxCountdownMs: Int64 = 10_000

    case hello(protocolVersion: Int, playerName: String, platform: String)
    case config(MatchConfig)
    case ready
    case imageFailed
    case start(countdownMs: Int64)
    case progress(tiles: [Int], moves: Int, tilesInPlace: Int)
    case solved(elapsedMs: Int64, moves: Int)
    case result(winnerIsHost: Bool, winnerTimeMs: Int64)
    case rematch
    case leave
    case ping
}

extension MatchMessage: Codable {
    private enum Key: String, CodingKey {
        case type, protocolVersion, playerName, platform
        case grid, seed, mode, customImage, imageBytes
        case countdownMs, tiles, moves, tilesInPlace, elapsedMs, winnerIsHost, winnerTimeMs
    }

    struct UnknownType: Error {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "hello":
            self = .hello(
                protocolVersion: try c.decode(Int.self, forKey: .protocolVersion),
                playerName: try c.decode(String.self, forKey: .playerName),
                platform: try c.decode(String.self, forKey: .platform)
            )
        case "config":
            self = .config(MatchConfig(
                grid: try c.decode(Int.self, forKey: .grid),
                seed: try c.decode(Int64.self, forKey: .seed),
                mode: try c.decode(Mode.self, forKey: .mode),
                customImage: try c.decode(Bool.self, forKey: .customImage),
                imageBytes: try c.decode(Int.self, forKey: .imageBytes)
            ))
        case "ready": self = .ready
        case "imageFailed": self = .imageFailed
        case "start": self = .start(countdownMs: try c.decodeIfPresent(Int64.self, forKey: .countdownMs) ?? MatchMessage.countdownMs)
        case "progress":
            self = .progress(
                tiles: try c.decode([Int].self, forKey: .tiles),
                moves: try c.decode(Int.self, forKey: .moves),
                tilesInPlace: try c.decode(Int.self, forKey: .tilesInPlace)
            )
        case "solved": self = .solved(elapsedMs: try c.decode(Int64.self, forKey: .elapsedMs), moves: try c.decode(Int.self, forKey: .moves))
        case "result":
            self = .result(winnerIsHost: try c.decode(Bool.self, forKey: .winnerIsHost), winnerTimeMs: try c.decode(Int64.self, forKey: .winnerTimeMs))
        case "rematch": self = .rematch
        case "leave": self = .leave
        case "ping": self = .ping
        default: throw UnknownType()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .hello(version, name, platform):
            try c.encode("hello", forKey: .type)
            try c.encode(version, forKey: .protocolVersion)
            try c.encode(name, forKey: .playerName)
            try c.encode(platform, forKey: .platform)
        case let .config(config):
            try c.encode("config", forKey: .type)
            try c.encode(config.grid, forKey: .grid)
            try c.encode(config.seed, forKey: .seed)
            try c.encode(config.mode, forKey: .mode)
            try c.encode(config.customImage, forKey: .customImage)
            try c.encode(config.imageBytes, forKey: .imageBytes)
        case .ready: try c.encode("ready", forKey: .type)
        case .imageFailed: try c.encode("imageFailed", forKey: .type)
        case let .start(countdownMs):
            try c.encode("start", forKey: .type)
            try c.encode(countdownMs, forKey: .countdownMs)
        case let .progress(tiles, moves, inPlace):
            try c.encode("progress", forKey: .type)
            try c.encode(tiles, forKey: .tiles)
            try c.encode(moves, forKey: .moves)
            try c.encode(inPlace, forKey: .tilesInPlace)
        case let .solved(elapsedMs, moves):
            try c.encode("solved", forKey: .type)
            try c.encode(elapsedMs, forKey: .elapsedMs)
            try c.encode(moves, forKey: .moves)
        case let .result(winnerIsHost, winnerTimeMs):
            try c.encode("result", forKey: .type)
            try c.encode(winnerIsHost, forKey: .winnerIsHost)
            try c.encode(winnerTimeMs, forKey: .winnerTimeMs)
        case .rematch: try c.encode("rematch", forKey: .type)
        case .leave: try c.encode("leave", forKey: .type)
        case .ping: try c.encode("ping", forKey: .type)
        }
    }
}

/// What a `PeerConnection` sends and receives.
enum Frame: Equatable {
    case control(MatchMessage)
    case image(Data)
}

enum MatchCodec {
    static func toRaw(_ frame: Frame) throws -> RawFrame {
        switch frame {
        case .control(let message): return RawFrame(kind: RawFrame.kindControl, payload: try JSONEncoder().encode(message))
        case .image(let bytes): return RawFrame(kind: RawFrame.kindImage, payload: bytes)
        }
    }

    /// Nil for unknown kinds or message types (e.g. from a newer app version).
    static func fromRaw(_ raw: RawFrame) -> Frame? {
        switch raw.kind {
        case RawFrame.kindControl: return (try? JSONDecoder().decode(MatchMessage.self, from: raw.payload)).map(Frame.control)
        case RawFrame.kindImage: return .image(raw.payload)
        default: return nil
        }
    }

    static func encode(_ frame: Frame) throws -> Data { try Framing.encode(toRaw(frame)) }
}
