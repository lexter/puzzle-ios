import Foundation

enum Appearance: String, CaseIterable { case light = "LIGHT", dark = "DARK", system = "SYSTEM" }

/// One leaderboard row. Field names match the stored JSON (shared with the previous app version).
struct Score: Codable, Equatable {
    let gridSize: Int
    let timeMs: Int64
    let moves: Int
    let playedAt: Int64
}

@MainActor
protocol ScoreStore: AnyObject {
    /// Top 10 for `gridSize`, fastest first, fewer moves breaking ties.
    func topTen(_ gridSize: Int) -> [Score]

    /// Saves `score`; returns true when it made the top 10.
    func record(_ score: Score) -> Bool
}

@MainActor
protocol SettingsStore: AnyObject {
    var appearance: Appearance { get }
    var gridSize: Int { get }
    var playerName: String? { get }
    func setAppearance(_ appearance: Appearance)
    func setGridSize(_ size: Int)
    func setPlayerName(_ name: String)
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
