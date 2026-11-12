/// Immutable board. `tiles` is row-major with 0 for the gap; tile `k` belongs at index `k`,
/// so the solved board is `0, 1, …, n² - 1`: the first (top-left) cell is always the gap.
struct PuzzleState: Equatable {
    static let minSize = 4
    static let maxSize = 10
    static let defaultSize = 4
    static let sizes = Array(minSize...maxSize)

    let size: Int
    let tiles: [Int]
    var moves: Int = 0

    init(size: Int, tiles: [Int], moves: Int = 0) {
        precondition((PuzzleState.minSize...PuzzleState.maxSize).contains(size), "size must be in \(PuzzleState.minSize)...\(PuzzleState.maxSize)")
        precondition(tiles.count == size * size, "expected \(size * size) tiles")
        self.size = size
        self.tiles = tiles
        self.moves = moves
    }

    /// Validating initializer for boards received from a peer: `tiles` must hold each of
    /// `0..<size²` exactly once (the board view keys tiles by number and traps on duplicates).
    init?(validating size: Int, tiles: [Int], moves: Int) {
        guard (PuzzleState.minSize...PuzzleState.maxSize).contains(size), tiles.count == size * size else { return nil }
        guard tiles.sorted() == Array(0..<(size * size)) else { return nil }
        self.init(size: size, tiles: tiles, moves: moves)
    }

    var gapIndex: Int { tiles.firstIndex(of: 0) ?? -1 }
    var tileCount: Int { size * size - 1 }
    var tilesInPlace: Int { tiles.enumerated().filter { $0.element != 0 && $0.element == $0.offset }.count }
    var isSolved: Bool { tilesInPlace == tileCount }

    func withMoves(_ moves: Int) -> PuzzleState { PuzzleState(size: size, tiles: tiles, moves: moves) }
}
