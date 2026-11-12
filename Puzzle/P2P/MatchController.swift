import Foundation

enum Role { case host, guest }

enum MatchPhase { case waiting, connected, configured, countdown, racing, finished, lost, solo }

enum LossReason { case disconnected, peerLeft, versionMismatch }

enum MatchNotice { case imageFallback, rematchRequested }

struct RaceResult: Equatable {
    let iWon: Bool
    let myTimeMs: Int64?
    let winnerTimeMs: Int64
}

/// Everything the lobby and race screens need, in one value.
struct MatchSnapshot: Equatable {
    var phase: MatchPhase = .waiting
    var peerName: String?
    var config: MatchConfig?
    /// JPEG of the host's photo, or nil for the bundled scenic picture.
    var imageBytes: Data?
    var peerReady = false
    var me: PuzzleState?
    var opponent: PuzzleState?
    var countdownEndsAt: Int64?
    var raceStartedAt: Int64?
    var mySolvedMs: Int64?
    var result: RaceResult?
    var lostReason: LossReason?
    var notice: MatchNotice?

    /// Clears everything about the current round.
    mutating func resetRound() {
        me = nil
        opponent = nil
        countdownEndsAt = nil
        raceStartedAt = nil
        mySolvedMs = nil
        result = nil
    }
}

/// Host/guest state machine for one connection. Everything runs on the main actor, so the
/// host's "first Solved wins" check is race-free.
@MainActor
final class MatchController: ObservableObject {
    let role: Role
    @Published private(set) var state = MatchSnapshot()

    private let connection: PeerConnection
    private let myName: String
    private let platform: String
    private let now: () -> Int64
    /// Guest-side check that the host's photo can be used.
    private let validateImage: (Data) -> Bool
    private var random: () -> Int64
    private let pingIntervalMs: Int64
    private let silenceTimeoutMs: Int64
    private let countdownMs: Int64

    private var tasks: [Task<Void, Never>] = []
    private var lastHeardAt: Int64
    private var pendingConfig: MatchConfig?
    private var leaving = false

    init(
        role: Role,
        connection: PeerConnection,
        myName: String,
        platform: String,
        now: @escaping () -> Int64,
        validateImage: @escaping (Data) -> Bool,
        random: @escaping () -> Int64 = { Int64.random(in: .min ... .max) },
        pingIntervalMs: Int64 = 2_000,
        silenceTimeoutMs: Int64 = 6_000,
        countdownMs: Int64 = MatchMessage.countdownMs
    ) {
        self.role = role
        self.connection = connection
        self.myName = myName
        self.platform = platform
        self.now = now
        self.validateImage = validateImage
        self.random = random
        self.pingIntervalMs = pingIntervalMs
        self.silenceTimeoutMs = silenceTimeoutMs
        self.countdownMs = countdownMs
        lastHeardAt = now()

        let incoming = connection.incoming
        tasks.append(Task { [weak self] in
            for await frame in incoming {
                guard let self else { return }
                self.lastHeardAt = self.now()
                self.handle(frame)
            }
            self?.onConnectionEnded()
        })
        tasks.append(Task { [weak self, pingIntervalMs] in
            while !Task.isCancelled {
                await sleep(ms: pingIntervalMs)
                guard !Task.isCancelled, let self else { return }
                self.send(.ping)
            }
        })
        tasks.append(Task { [weak self, silenceTimeoutMs] in
            while !Task.isCancelled {
                await sleep(ms: silenceTimeoutMs / 12)
                guard !Task.isCancelled, let self else { return }
                if self.now() - self.lastHeardAt > silenceTimeoutMs {
                    self.lose(.disconnected)
                    self.connection.close()
                    return
                }
            }
        })
        send(.hello(protocolVersion: protocolVersion, playerName: myName, platform: platform))
    }

    /// Race stopwatch for the UI.
    func elapsedNow() -> Int64 {
        state.mySolvedMs ?? state.raceStartedAt.map { now() - $0 } ?? 0
    }

    func millisUntilStart() -> Int64 { max((state.countdownEndsAt.map { $0 - now() }) ?? 0, 0) }

    // MARK: Host actions

    /// Sets up (or re-sets up) the match with a fresh seed and sends it to the guest.
    func configure(grid: Int, mode: Mode, imageBytes: Data?) {
        precondition(role == .host, "only the host configures")
        let config = MatchConfig(grid: grid, seed: random(), mode: mode, customImage: imageBytes != nil, imageBytes: imageBytes?.count ?? 0)
        var next = state
        next.phase = .configured
        next.config = config
        next.imageBytes = imageBytes
        next.peerReady = false
        next.resetRound()
        next.notice = state.notice == .imageFallback ? state.notice : nil
        state = next
        send(.config(config))
        if let imageBytes { connection.send(.image(imageBytes)) }
    }

    func startRace() {
        precondition(role == .host && state.phase == .configured && state.peerReady, "guest not ready")
        send(.start(countdownMs: countdownMs))
        beginCountdown(countdownMs)
    }

    // MARK: Both

    func tapTile(_ tileId: Int) {
        let current = state
        guard current.phase == .racing || current.phase == .solo else { return }
        guard current.mySolvedMs == nil else { return } // solved: waiting for the host's Result
        guard let board = current.me else { return }
        let next = PuzzleEngine.slideTile(board, tileId)
        guard next.moves != board.moves else { return }
        state.me = next
        if current.phase == .racing { send(.progress(tiles: next.tiles, moves: next.moves, tilesInPlace: next.tilesInPlace)) }
        guard next.isSolved else { return }
        let time = elapsedNow()
        if current.phase == .solo {
            state.mySolvedMs = time
        } else if role == .host {
            decide(hostWon: true, winnerTimeMs: time)
        } else {
            state.mySolvedMs = time
            send(.solved(elapsedMs: time, moves: next.moves))
        }
    }

    /// Host: new board with the same settings. Guest: asks the host for one.
    func rematch() {
        guard let config = state.config else { return }
        if role == .host { configure(grid: config.grid, mode: config.mode, imageBytes: state.imageBytes) } else { send(.rematch) }
    }

    /// After a lost connection mid-race: keep solving locally, unranked.
    func continueSolo() {
        if state.phase == .lost, state.me != nil, state.raceStartedAt != nil {
            state.phase = .solo
        }
    }

    /// Test hook: replace this player's board.
    func debugSetBoard(_ board: PuzzleState) { state.me = board }

    func dismissNotice() { state.notice = nil }

    func leave() {
        leaving = true
        let connection = self.connection
        let tasks = self.tasks
        Task {
            await connection.sendAndWait(.control(.leave))
            connection.close()
            tasks.forEach { $0.cancel() }
        }
    }

    // MARK: Incoming

    private func handle(_ frame: Frame) {
        switch frame {
        case .image(let bytes): onImage(bytes)
        case .control(let message): onMessage(message)
        }
    }

    private func onMessage(_ message: MatchMessage) {
        switch message {
        case .hello(let version, let name, _): onHello(version: version, name: name)
        case .config(let config): if role == .guest { onConfig(config) }
        case .ready: if role == .host { state.peerReady = true }
        case .imageFailed: if role == .host { onImageFailed() }
        case .start(let countdownMs):
            if role == .guest && state.phase == .configured { beginCountdown(min(max(countdownMs, 0), MatchMessage.maxCountdownMs)) }
        case let .progress(tiles, moves, _): onProgress(tiles: tiles, moves: moves)
        case .solved(let elapsedMs, _): if role == .host { decide(hostWon: false, winnerTimeMs: elapsedMs) }
        case let .result(winnerIsHost, winnerTimeMs): if role == .guest { finish(iWon: !winnerIsHost, winnerTimeMs: winnerTimeMs) }
        case .rematch: if role == .host { state.notice = .rematchRequested }
        case .leave: lose(.peerLeft)
        case .ping: break
        }
    }

    private func onHello(version: Int, name: String) {
        guard version == protocolVersion else {
            lose(.versionMismatch)
            leave()
            return
        }
        state.peerName = name
        if state.phase == .waiting { state.phase = .connected }
    }

    private func onConfig(_ config: MatchConfig) {
        guard config.isValid else { return }
        pendingConfig = config
        if !config.customImage { markReady(config, imageBytes: nil) }
    }

    private func onImage(_ bytes: Data) {
        guard role == .guest, let config = pendingConfig else { return }
        if validateImage(bytes) { markReady(config, imageBytes: bytes) } else { send(.imageFailed) }
    }

    private func markReady(_ config: MatchConfig, imageBytes: Data?) {
        pendingConfig = nil
        var next = state
        next.phase = .configured
        next.config = config
        next.imageBytes = imageBytes
        next.resetRound()
        next.notice = nil
        state = next
        send(.ready)
    }

    private func onImageFailed() {
        guard let config = state.config else { return }
        state.notice = .imageFallback
        configure(grid: config.grid, mode: config.mode, imageBytes: nil)
    }

    private func onProgress(tiles: [Int], moves: Int) {
        guard let grid = state.config?.grid, let board = PuzzleState(validating: grid, tiles: tiles, moves: moves) else { return }
        state.opponent = board
    }

    // MARK: Transitions

    private func beginCountdown(_ durationMs: Int64) {
        state.phase = .countdown
        state.countdownEndsAt = now() + durationMs
        Task { [weak self] in
            await sleep(ms: durationMs)
            guard let self, self.state.phase == .countdown else { return }
            self.beginRace()
        }
    }

    private func beginRace() {
        guard let config = state.config else { return }
        let board = PuzzleEngine.shuffled(config.grid, seed: config.seed)
        var next = state
        next.phase = .racing
        next.me = board
        next.opponent = board
        next.raceStartedAt = now()
        state = next
    }

    /// Host only: the first solve it learns about wins, and only one Result is ever sent.
    private func decide(hostWon: Bool, winnerTimeMs: Int64) {
        guard state.phase == .racing, state.result == nil else { return }
        let myTime = hostWon ? winnerTimeMs : state.mySolvedMs
        var next = state
        next.phase = .finished
        next.mySolvedMs = myTime
        next.result = RaceResult(iWon: hostWon, myTimeMs: myTime, winnerTimeMs: winnerTimeMs)
        state = next
        send(.result(winnerIsHost: hostWon, winnerTimeMs: winnerTimeMs))
    }

    private func finish(iWon: Bool, winnerTimeMs: Int64) {
        var next = state
        next.phase = .finished
        next.result = RaceResult(iWon: iWon, myTimeMs: iWon ? state.mySolvedMs : nil, winnerTimeMs: winnerTimeMs)
        state = next
    }

    private func lose(_ reason: LossReason) {
        guard !leaving, state.phase != .lost, state.phase != .solo else { return }
        var next = state
        next.phase = .lost
        next.lostReason = reason
        state = next
    }

    private func onConnectionEnded() { lose(.disconnected) }

    private func send(_ message: MatchMessage) { connection.send(.control(message)) }
}

/// `Task.sleep` that just returns early when cancelled.
func sleep(ms: Int64) async {
    try? await Task.sleep(nanoseconds: UInt64(min(max(ms, 0), Int64.max / 1_000_000)) * 1_000_000)
}
