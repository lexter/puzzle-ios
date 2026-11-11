enum PuzzleEngine {

    /// The solved board: the gap sits in the first (top-left) cell, tiles 1… follow in order.
    static func solved(_ size: Int) -> PuzzleState { PuzzleState(size: size, tiles: Array(0..<(size * size))) }

    /// A solvable, not-yet-solved board with the gap in the first cell. The same `seed` always
    /// gives the same board, on iOS and Android alike.
    static func shuffled(_ size: Int, seed: Int64) -> PuzzleState {
        var random = KotlinRandom(seed: seed)
        var shuffledTiles = Array(0..<(size * size))
        shuffledTiles.kotlinShuffle(using: &random)
        // Sliding keeps solvability, so parking the gap first doesn't disturb the parity fix below.
        var tiles = parkGap(PuzzleState(size: size, tiles: shuffledTiles)).tiles
        // Swapping two numbered tiles flips solvability parity.
        if !isSolvable(size, tiles) { swapNumbered(&tiles, first: true) }
        if PuzzleState(size: size, tiles: tiles).isSolved {
            // Two swaps keep it solvable but no longer solved.
            swapNumbered(&tiles, first: false)
            swapNumbered(&tiles, first: true)
        }
        return PuzzleState(size: size, tiles: tiles)
    }

    /// A scramble made of real slides, for animating: each frame is one legal move from the
    /// previous, starting from the solved board. The gap heads in a random direction each step
    /// (never straight back the way it came) and drags 1…all tiles in that line along. Finally
    /// the gap is slid back to the first cell. The last frame is never solved. The same `seed`
    /// always gives the same frames.
    static func shuffleWalk(_ size: Int, seed: Int64, steps: Int) -> [PuzzleState] {
        var random = KotlinRandom(seed: seed)
        var frames: [PuzzleState] = []
        frames.reserveCapacity(steps + 1)
        var board = solved(size)
        var lastDirection: Direction?
        var taken = 0
        while true {
            while taken < steps || board.isSolved {
                let gap = board.gapIndex
                let options = Direction.allCases.filter { $0 != lastDirection?.opposite && reach(size, gap, $0) > 0 }
                let direction = options[random.nextInt(until: options.count)]
                let distance = 1 + random.nextInt(until: reach(size, gap, direction))
                board = slide(board, gap + direction.step(size) * distance)
                lastDirection = direction
                frames.append(board)
                taken += 1
            }
            for parkMove in parkGapMoves(board) {
                board = slide(board, parkMove)
                frames.append(board)
            }
            if !board.isSolved { break }
            lastDirection = nil
        }
        return frames.map { $0.withMoves(0) }
    }

    /// Slides the gap to the first cell: along its row to column 0, then up column 0.
    private static func parkGap(_ state: PuzzleState) -> PuzzleState {
        parkGapMoves(state).reduce(state) { slide($0, $1) }
    }

    /// The cell indices to tap, in order, to bring the gap of `state` to the first cell.
    private static func parkGapMoves(_ state: PuzzleState) -> [Int] {
        let n = state.size
        let gap = state.gapIndex
        var moves: [Int] = []
        if gap % n != 0 { moves.append(gap - gap % n) }
        if gap / n != 0 { moves.append(0) }
        return moves
    }

    /// Declaration order matters: the shuffle walk picks from these in this order.
    private enum Direction: CaseIterable {
        case up, down, left, right

        var dRow: Int { switch self { case .up: return -1; case .down: return 1; default: return 0 } }
        var dCol: Int { switch self { case .left: return -1; case .right: return 1; default: return 0 } }
        var opposite: Direction { switch self { case .up: return .down; case .down: return .up; case .left: return .right; case .right: return .left } }
        func step(_ size: Int) -> Int { dRow * size + dCol }
    }

    /// How many cells the gap can travel from `gap` in `direction`.
    private static func reach(_ size: Int, _ gap: Int, _ direction: Direction) -> Int {
        let row = gap / size
        let col = gap % size
        switch direction {
        case .up: return row
        case .down: return size - 1 - row
        case .left: return col
        case .right: return size - 1 - col
        }
    }

    static func isSolvable(_ size: Int, _ tiles: [Int]) -> Bool {
        let numbers = tiles.filter { $0 != 0 }
        var inversions = 0
        for i in numbers.indices {
            for j in (i + 1)..<numbers.count where numbers[i] > numbers[j] { inversions += 1 }
        }
        if size % 2 == 1 { return inversions % 2 == 0 }
        // Each vertical slide flips inversion parity and moves the gap one row. The solved board
        // has no inversions and its gap in the top row (n rows from the bottom, an even number).
        let gapRowFromBottom = size - (tiles.firstIndex(of: 0) ?? 0) / size
        return (inversions + gapRowFromBottom) % 2 == 0
    }

    /// Taps the cell at `index`. If it shares a row or column with the gap, every tile between
    /// it and the gap moves one step toward the gap (one move). Otherwise returns `state` unchanged.
    static func slide(_ state: PuzzleState, _ index: Int) -> PuzzleState {
        let n = state.size
        let gap = state.gapIndex
        guard state.tiles.indices.contains(index), index != gap else { return state }
        let sameRow = index / n == gap / n
        let sameColumn = index % n == gap % n
        guard sameRow || sameColumn else { return state }
        let step = sameRow ? (index < gap ? -1 : 1) : (index < gap ? -n : n)
        var tiles = state.tiles
        var at = gap
        while at != index {
            tiles[at] = tiles[at + step]
            at += step
        }
        tiles[index] = 0
        return PuzzleState(size: n, tiles: tiles, moves: state.moves + 1)
    }

    /// Same as `slide` but addressed by tile number, so stale indices can't misapply a tap.
    static func slideTile(_ state: PuzzleState, _ tileId: Int) -> PuzzleState {
        guard tileId != 0, let index = state.tiles.firstIndex(of: tileId) else { return state }
        return slide(state, index)
    }

    private static func swapNumbered(_ tiles: inout [Int], first: Bool) {
        let numbered = tiles.indices.filter { tiles[$0] != 0 }
        let (a, b) = first ? (numbered[0], numbered[1]) : (numbered[numbered.count - 2], numbered[numbered.count - 1])
        tiles.swapAt(a, b)
    }
}
