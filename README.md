# Slide Puzzle (iOS)

Native SwiftUI rewrite of the Compose Multiplatform app in `../puzzle`. Same features and behavior: 4×4 to 10×10 grids, time attack and free play, a per-size top-10 leaderboard, and offline LAN races against Android or iPhone.

## Build

Open `Puzzle.xcodeproj` in Xcode and run the `Puzzle` scheme. Team, bundle ID and app name are in `Configuration/Config.xcconfig`.

```bash
xcodebuild -project Puzzle.xcodeproj -scheme Puzzle -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Minimum iOS is 15.0. There are no third-party dependencies.

## Layout

- `Puzzle/Game`: board model, shuffle, clock. `KotlinRandom.swift` is a bit-exact port of Kotlin's `Random(seed)`, so both platforms shuffle the same race board from the host's seed.
- `Puzzle/P2P`: wire framing, JSON messages, Network.framework sockets, Bonjour (`_slidepuzzle._tcp`), and the match state machine.
- `Puzzle/Data`: settings and scores in `UserDefaults`. On first launch, `LegacyPreferencesImport` copies settings and scores from the old app's DataStore file.
- `Puzzle/UI`: SwiftUI screens and the Candy Pop glass theme.
- `PuzzleTests`: golden shuffle values captured from Kotlin, wire-format compatibility checks, and storage tests.
