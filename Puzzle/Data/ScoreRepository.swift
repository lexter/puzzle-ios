import Foundation

/// Leaderboard kept as one small JSON list per grid size (at most 10 rows each).
@MainActor
final class ScoreRepository: ObservableObject, ScoreStore {
    private static let limit = 10
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func topTen(_ gridSize: Int) -> [Score] { decode(defaults.string(forKey: Self.key(gridSize))) }

    func record(_ score: Score) -> Bool {
        var all = decode(defaults.string(forKey: Self.key(score.gridSize)))
        let index = all.count
        all.append(score)
        // Stable sort by (time, moves); the new score is last among equals, as in a stable sort.
        let ranked = all.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.timeMs != rhs.element.timeMs { return lhs.element.timeMs < rhs.element.timeMs }
                if lhs.element.moves != rhs.element.moves { return lhs.element.moves < rhs.element.moves }
                return lhs.offset < rhs.offset
            }
            .prefix(Self.limit)
        let madeTopTen = ranked.contains { $0.offset == index }
        let rows = ranked.map(\.element)
        if let data = try? JSONEncoder().encode(rows), let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: Self.key(score.gridSize))
        }
        objectWillChange.send()
        return madeTopTen
    }

    private func decode(_ raw: String?) -> [Score] {
        guard let data = raw?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Score].self, from: data)) ?? []
    }

    static func key(_ gridSize: Int) -> String { "scores_\(gridSize)" }
}
