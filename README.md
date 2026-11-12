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

## Git hooks

```bash
scripts/install-hooks.sh
```

- **pre-commit**: SwiftLint (`--strict`, config in `.swiftlint.yml`) on the staged Swift files, plus `scripts/privacy-guard.sh`. Needs `brew install swiftlint`.
- **pre-push**: builds the app and test bundle for the simulator (`xcodebuild build-for-testing`).

Skip once with `--no-verify`.

## CI (`.github/workflows/ci.yml`)

Runs on pushes to `main`, pull requests and manual dispatch.

1. **Code integrity review**: gitleaks over the full history, `scripts/privacy-guard.sh` (blocks the device name, tracking identifiers, console logging, cleartext HTTP and ATS exceptions, and checks the privacy manifest), and mobsfscan (OWASP MASVS rules; justified exceptions in `.mobsf`).
2. **Lint, build and unit test**: SwiftLint, then `xcodebuild test` on the newest iPhone simulator of the newest iOS runtime on the runner (`scripts/ci/latest-simulator.sh`).
3. **Firebase App Distribution**: on `main` and manual runs, after 1 and 2 pass: an ad-hoc (release-testing) IPA, build number = run number. Skipped with a notice until configured.

Distribution needs a paid Apple Developer account (ad-hoc signing isn't available to free personal teams) and these repository settings:

| Name | Kind | Value |
| --- | --- | --- |
| `IOS_DIST_CERT_P12_BASE64` | secret | Apple Distribution certificate + key exported as .p12, base64-encoded |
| `IOS_DIST_CERT_PASSWORD` | secret | Password of that .p12 |
| `IOS_ADHOC_PROFILE_BASE64` | secret | Ad Hoc provisioning profile for `com.lexterlabra.puzzle`, base64-encoded (testers' devices must be in it) |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | secret | Google service account key with the Firebase App Distribution Admin role |
| `FIREBASE_IOS_APP_ID` | variable | Firebase iOS app ID (`1:…:ios:…`) |
| `FIREBASE_TESTER_GROUPS` | variable | Optional; comma-separated group aliases (default `testers`) |

The team ID and profile name are read from the profile.
