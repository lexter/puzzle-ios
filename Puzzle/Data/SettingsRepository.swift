import Foundation

/// Settings kept in `UserDefaults`, published so the UI follows changes (e.g. appearance).
@MainActor
final class SettingsRepository: ObservableObject, SettingsStore {
    private static let maxNameLength = 24
    private enum Key {
        static let appearance = "appearance"
        static let gridSize = "gridSize"
        static let playerName = "playerName"
    }

    private let defaults: UserDefaults

    @Published private(set) var appearance: Appearance
    @Published private(set) var gridSize: Int
    @Published private(set) var playerName: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        let storedGrid = defaults.object(forKey: Key.gridSize) as? Int ?? PuzzleState.defaultSize
        gridSize = storedGrid.clamped(to: PuzzleState.minSize...PuzzleState.maxSize)
        playerName = defaults.string(forKey: Key.playerName)
    }

    func setAppearance(_ appearance: Appearance) {
        defaults.set(appearance.rawValue, forKey: Key.appearance)
        self.appearance = appearance
    }

    func setGridSize(_ size: Int) {
        let clamped = size.clamped(to: PuzzleState.minSize...PuzzleState.maxSize)
        defaults.set(clamped, forKey: Key.gridSize)
        gridSize = clamped
    }

    func setPlayerName(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        defaults.set(trimmed, forKey: Key.playerName)
        playerName = trimmed
    }
}
