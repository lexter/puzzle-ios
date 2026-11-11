import CoreGraphics
import Foundation

enum GamePhase { case ready, shuffling, countdown, playing, won }

/// The visible scramble when a game starts: `shuffleSteps` slides, one every `shuffleStepMs`.
let shuffleStepMs: Int64 = 100
let shuffleSteps = 50

/// After the scramble, a 3-2-1 count runs before play (and the timer) starts.
let countdownFrom = 3
let countdownStepMs: Int64 = 1_000

/// Solo game: scramble animation, countdown, play, and recording time-based wins.
@MainActor
final class GameModel: ObservableObject, ScreenModel {
    let mode: Mode
    @Published private(set) var puzzle: PuzzleState
    @Published private(set) var phase = GamePhase.ready
    @Published private(set) var customImage: CGImage?
    @Published private(set) var elapsedMs: Int64 = 0
    @Published private(set) var pausedHidden = false
    @Published private(set) var loadingPhoto = false
    @Published private(set) var message: UserMessage?
    @Published private(set) var newBest = false
    /// The number on screen during `.countdown`; 0 otherwise.
    @Published private(set) var countdown = 0

    private let settings: SettingsStore
    private let scores: ScoreStore
    private let clock: GameClock
    private let seedSource: () -> Int64
    private let shuffleFrames: (Int, Int64) -> [PuzzleState]
    private let now: () -> Int64
    private var shuffleTask: Task<Void, Never>?
    private(set) lazy var picker = ImagePicker { [weak self] in self?.setPicture($0) }

    init(
        mode: Mode,
        settings: SettingsStore,
        scores: ScoreStore,
        clock: GameClock = GameClock(),
        seedSource: @escaping () -> Int64 = { Int64.random(in: .min ... .max) },
        shuffleFrames: @escaping (Int, Int64) -> [PuzzleState] = { PuzzleEngine.shuffleWalk($0, seed: $1, steps: shuffleSteps) },
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        initialImage: CGImage? = nil
    ) {
        self.mode = mode
        self.settings = settings
        self.scores = scores
        self.clock = clock
        self.seedSource = seedSource
        self.shuffleFrames = shuffleFrames
        self.now = now
        customImage = initialImage
        puzzle = PuzzleEngine.solved(settings.gridSize)
    }

    func onCleared() { shuffleTask?.cancel() }

    /// Live stopwatch value; the screen polls it while playing.
    func elapsedNow() -> Int64 { clock.elapsedMs }

    func start() {
        guard phase == .ready else { return }
        let frames = shuffleFrames(puzzle.size, seedSource())
        phase = .shuffling
        newBest = false
        shuffleTask = Task { [weak self] in
            for frame in frames {
                guard let self, !Task.isCancelled else { return }
                self.puzzle = frame.withMoves(0)
                await sleep(ms: shuffleStepMs)
            }
            for count in stride(from: countdownFrom, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.phase = .countdown
                self.countdown = count
                await sleep(ms: countdownStepMs)
            }
            guard let self, !Task.isCancelled else { return }
            self.phase = .playing
            self.countdown = 0
            if self.mode == .timeBased { self.clock.start() } else { self.clock.reset() }
        }
    }

    func tapTile(_ tileId: Int) {
        guard phase == .playing, !pausedHidden else { return }
        let next = PuzzleEngine.slideTile(puzzle, tileId)
        guard next.moves != puzzle.moves else { return }
        guard next.isSolved else {
            puzzle = next
            return
        }
        clock.pause()
        let elapsed = clock.elapsedMs
        puzzle = next
        phase = .won
        elapsedMs = elapsed
        if mode == .timeBased {
            newBest = scores.record(Score(gridSize: next.size, timeMs: elapsed, moves: next.moves, playedAt: now()))
        }
    }

    func setGridSize(_ size: Int) {
        let clamped = size.clamped(to: PuzzleState.minSize...PuzzleState.maxSize)
        settings.setGridSize(clamped)
        reset(to: clamped)
    }

    func setPicture(_ result: PickResult) {
        switch result {
        case .cancelled: break
        case .permissionDenied: message = .cameraDenied
        case .picked(let bytes):
            loadingPhoto = true
            Task {
                let prepared = await Task.detached(priority: .userInitiated) { PuzzleImage.prepare(bytes) }.value
                loadingPhoto = false
                switch prepared {
                case .success(let image): customImage = image
                case .failure(let error): message = .from(error)
                }
            }
        }
    }

    func useScenic() { customImage = nil }

    func dismissMessage() { message = nil }

    func onBackground() {
        guard phase == .playing, mode == .timeBased, !pausedHidden else { return }
        clock.pause()
        pausedHidden = true
        elapsedMs = clock.elapsedMs
    }

    func onForeground() {
        guard pausedHidden else { return }
        clock.resume()
        pausedHidden = false
    }

    func playAgain() { reset(to: puzzle.size) }

    private func reset(to size: Int) {
        shuffleTask?.cancel()
        shuffleTask = nil
        clock.reset()
        puzzle = PuzzleEngine.solved(size)
        phase = .ready
        elapsedMs = 0
        pausedHidden = false
        newBest = false
        countdown = 0
    }
}
