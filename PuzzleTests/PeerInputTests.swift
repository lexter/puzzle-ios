import XCTest
@testable import Puzzle

/// Messages from a peer are untrusted: malformed values must be dropped or clamped, never trap.
@MainActor
final class PeerInputTests: XCTestCase {
    func testValidatingBoardRejectsNonPermutations() {
        XCTAssertNotNil(PuzzleState(validating: 4, tiles: Array(0..<16), moves: 0))
        XCTAssertNil(PuzzleState(validating: 4, tiles: Array(repeating: 0, count: 16), moves: 0))
        XCTAssertNil(PuzzleState(validating: 4, tiles: Array(1...16), moves: 0))
        XCTAssertNil(PuzzleState(validating: 4, tiles: Array(0..<15), moves: 0))
        XCTAssertNil(PuzzleState(validating: 100_000, tiles: [], moves: 0))
    }

    func testGuestIgnoresOutOfRangeGrid() async {
        let (controller, peer) = makeGuest()
        for grid in [-1, 0, 3, 11, 100_000, Int.max] {
            peer.deliver(.config(MatchConfig(grid: grid, seed: 1, mode: .free, customImage: false, imageBytes: 0)))
        }
        await settle()
        XCTAssertNil(controller.state.config)
        XCTAssertNotEqual(controller.state.phase, .configured)
    }

    func testGuestIgnoresDuplicateTileProgress() async {
        let (controller, peer) = makeGuest()
        peer.deliver(.config(MatchConfig(grid: 4, seed: 1, mode: .free, customImage: false, imageBytes: 0)))
        peer.deliver(.progress(tiles: Array(repeating: 0, count: 16), moves: 1, tilesInPlace: 0))
        await settle()
        XCTAssertEqual(controller.state.config?.grid, 4)
        XCTAssertNil(controller.state.opponent)
    }

    func testGuestClampsHugeCountdown() async {
        let clock: Int64 = 1_000
        let (controller, peer) = makeGuest(now: { clock })
        peer.deliver(.config(MatchConfig(grid: 4, seed: 1, mode: .free, customImage: false, imageBytes: 0)))
        peer.deliver(.start(countdownMs: .max))
        await settle()
        XCTAssertEqual(controller.state.phase, .countdown)
        XCTAssertEqual(controller.state.countdownEndsAt, clock + MatchMessage.maxCountdownMs)
    }

    func testSleepWithHugeDurationDoesNotTrap() async {
        let task = Task { await sleep(ms: .max) }
        task.cancel()
        await task.value
    }

    // MARK: Helpers

    private func makeGuest(now: @escaping () -> Int64 = { 0 }) -> (MatchController, FakePeer) {
        let peer = FakePeer()
        let controller = MatchController(
            role: .guest,
            connection: peer,
            myName: "Guest",
            platform: "ios",
            now: now,
            validateImage: { _ in true },
            pingIntervalMs: 60_000,
            silenceTimeoutMs: 600_000
        )
        addTeardownBlock { @MainActor in peer.close() }
        return (controller, peer)
    }

    /// Lets the controller's receive loop drain what was delivered.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

@MainActor
private final class FakePeer: PeerConnection {
    let incoming: AsyncStream<Frame>
    private let continuation: AsyncStream<Frame>.Continuation
    private(set) var isClosed = false

    init() {
        var captured: AsyncStream<Frame>.Continuation!
        incoming = AsyncStream { captured = $0 }
        continuation = captured
    }

    func deliver(_ message: MatchMessage) { continuation.yield(.control(message)) }
    func send(_ frame: Frame) {}
    func sendAndWait(_ frame: Frame) async {}

    func close() {
        isClosed = true
        continuation.finish()
    }
}
