import Foundation

/// Milliseconds from a monotonic clock (unaffected by wall-clock changes).
func monotonicMillis() -> Int64 {
    Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
}

/// Stopwatch driven by an injectable monotonic millisecond source.
final class GameClock {
    private let now: () -> Int64
    private var accumulatedMs: Int64 = 0
    private var runningSince: Int64?
    private var paused = false

    init(now: @escaping () -> Int64 = monotonicMillis) { self.now = now }

    var isRunning: Bool { runningSince != nil }
    var elapsedMs: Int64 { accumulatedMs + (runningSince.map { now() - $0 } ?? 0) }

    func start() {
        accumulatedMs = 0
        paused = false
        runningSince = now()
    }

    func pause() {
        guard let since = runningSince else { return }
        accumulatedMs += now() - since
        runningSince = nil
        paused = true
    }

    func resume() {
        guard paused else { return }
        paused = false
        runningSince = now()
    }

    func reset() {
        accumulatedMs = 0
        runningSince = nil
        paused = false
    }
}

/// `mm:ss.t`, minutes keep counting past 59.
func formatElapsed(_ ms: Int64) -> String {
    let tenths = max(ms, 0) / 100
    let minutes = tenths / 600
    let seconds = (tenths / 10) % 60
    return String(format: "%02lld:%02lld.%lld", minutes, seconds, tenths % 10)
}
