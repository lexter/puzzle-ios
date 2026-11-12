import XCTest
@testable import Puzzle

/// Golden values come from Kotlin's `kotlin.random.Random` / `PuzzleEngine` (the Android app),
/// so a race between an iPhone and an Android phone shuffles the same board.
final class PuzzleEngineTests: XCTestCase {
    func testKotlinRandomMatchesKotlin() {
        var random = KotlinRandom(seed: Int64(42))
        XCTAssertEqual((0..<5).map { _ in random.nextInt() }, [972016666, 1740578880, -408207414, -112774692, 1162768683])
        var bounded = KotlinRandom(seed: Int64(-1234567890123))
        XCTAssertEqual((0..<8).map { bounded.nextInt(until: $0 + 3) }, [0, 1, 1, 1, 5, 3, 8, 6])
    }

    func testShuffledMatchesKotlin() {
        XCTAssertEqual(PuzzleEngine.shuffled(4, seed: 42).tiles, [0, 14, 6, 7, 15, 4, 8, 12, 2, 10, 11, 1, 5, 9, 13, 3])
        XCTAssertEqual(
            PuzzleEngine.shuffled(5, seed: -1234567890123).tiles,
            [0, 10, 8, 7, 20, 6, 21, 4, 17, 19, 22, 2, 12, 1, 3, 18, 11, 23, 13, 16, 24, 15, 9, 14, 5]
        )
        XCTAssertEqual(
            PuzzleEngine.shuffled(10, seed: .max).tiles,
            // swiftlint:disable:next line_length
            [0, 79, 49, 30, 62, 41, 40, 54, 9, 84, 33, 85, 68, 25, 95, 23, 45, 64, 92, 43, 38, 18, 52, 21, 81, 82, 42, 65, 35, 51, 94, 10, 89, 69, 83, 91, 97, 76, 12, 5, 37, 99, 58, 6, 71, 32, 27, 74, 13, 31, 60, 39, 61, 34, 67, 14, 77, 8, 87, 96, 98, 66, 46, 90, 22, 3, 50, 88, 19, 78, 4, 11, 17, 36, 56, 93, 72, 48, 28, 53, 26, 80, 44, 70, 29, 57, 2, 63, 20, 15, 16, 55, 7, 73, 47, 24, 75, 1, 59, 86]
        )
    }

    func testShuffleWalkMatchesKotlin() {
        let frames = PuzzleEngine.shuffleWalk(4, seed: 7, steps: 50)
        XCTAssertEqual(frames.count, 51)
        XCTAssertEqual(frames.last?.tiles, [0, 4, 11, 15, 3, 2, 7, 14, 1, 5, 6, 13, 8, 12, 9, 10])
    }

    func testShufflesAreSolvableAndNotSolved() {
        for n in 4...10 {
            for seed in Int64(0)..<200 {
                let state = PuzzleEngine.shuffled(n, seed: seed)
                XCTAssertTrue(PuzzleEngine.isSolvable(n, state.tiles), "n=\(n) seed=\(seed)")
                XCTAssertFalse(state.isSolved, "n=\(n) seed=\(seed)")
                XCTAssertEqual(Set(state.tiles), Set(0..<(n * n)))
                XCTAssertEqual(state.gapIndex, 0)
            }
        }
    }

    func testShuffleWalkIsLegalAndScrambled() {
        for n in 4...10 {
            for seed in Int64(0)..<50 {
                let frames = PuzzleEngine.shuffleWalk(n, seed: seed, steps: 50)
                XCTAssertGreaterThanOrEqual(frames.count, 50)
                var previous = PuzzleEngine.solved(n)
                for frame in frames {
                    let gap = previous.gapIndex
                    let next = frame.gapIndex
                    XCTAssertTrue(gap / n == next / n || gap % n == next % n)
                    XCTAssertEqual(PuzzleEngine.slide(previous, next).tiles, frame.tiles)
                    previous = frame
                }
                XCTAssertFalse(frames.last!.isSolved)
                XCTAssertTrue(PuzzleEngine.isSolvable(n, frames.last!.tiles))
                XCTAssertEqual(frames.last!.gapIndex, 0)
            }
        }
    }

    func testParity() {
        XCTAssertFalse(PuzzleEngine.isSolvable(4, Array(0...13) + [15, 14]))
        var swapped = Array(0...24)
        swapped.swapAt(1, 2)
        XCTAssertTrue(PuzzleEngine.isSolvable(5, Array(0...24)))
        XCTAssertFalse(PuzzleEngine.isSolvable(5, swapped))
    }

    func testSlides() {
        let adjacent = PuzzleEngine.slide(PuzzleEngine.solved(4), 1)
        XCTAssertEqual(adjacent.tiles[0], 1)
        XCTAssertEqual(adjacent.tiles[1], 0)
        XCTAssertEqual(adjacent.moves, 1)
        XCTAssertEqual(adjacent.tilesInPlace, 14)

        let column = PuzzleEngine.slide(PuzzleEngine.solved(4), 12)
        XCTAssertEqual([column.tiles[0], column.tiles[4], column.tiles[8], column.tiles[12]], [4, 8, 12, 0])

        let row = PuzzleEngine.slide(PuzzleEngine.solved(4), 3)
        XCTAssertEqual(Array(row.tiles[0..<4]), [1, 2, 3, 0])

        let board = PuzzleEngine.solved(4)
        XCTAssertEqual(PuzzleEngine.slide(board, 5), board)
        XCTAssertEqual(PuzzleEngine.slide(board, 0), board)
        XCTAssertEqual(PuzzleEngine.slideTile(board, 1).tiles[0], 1)
    }

    func testFormatElapsed() {
        XCTAssertEqual(formatElapsed(0), "00:00.0")
        XCTAssertEqual(formatElapsed(61_234), "01:01.2")
        XCTAssertEqual(formatElapsed(3_600_000 * 2), "120:00.0")
        XCTAssertEqual(formatElapsed(-5), "00:00.0")
    }
}
