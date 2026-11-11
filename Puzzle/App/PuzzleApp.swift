import SwiftUI

let appName = "Slide Puzzle"

/// Hand-wired dependencies, one instance per process.
@MainActor
final class AppContainer {
    let settings: SettingsRepository
    let scores: ScoreRepository
    let matchHub: MatchHub
    let photos: PhotoSelection

    init() {
        LegacyPreferencesImport.runIfNeeded()
        settings = SettingsRepository()
        scores = ScoreRepository()
        matchHub = MatchHub()
        photos = PhotoSelection()
    }
}

@main
struct PuzzleApp: App {
    @StateObject private var navigator = Navigator()
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(container: container, settings: container.settings, navigator: navigator)
        }
    }
}

struct RootView: View {
    let container: AppContainer
    @ObservedObject var settings: SettingsRepository
    @ObservedObject var navigator: Navigator

    var body: some View {
        let entry = navigator.current
        PuzzleTheme(appearance: settings.appearance) {
            ScreenContent(entry: entry, navigator: navigator, container: container)
                .id(entry.id)
        }
    }
}

private struct ScreenContent: View {
    let entry: NavEntry
    let navigator: Navigator
    let container: AppContainer

    var body: some View {
        switch entry.screen {
        case .landing:
            LandingScreen(
                onPlay: { players, mode in navigator.push(players == .single ? .game(mode) : .lobby(mode)) },
                onLeaderboard: { navigator.push(.leaderboard) }
            )
        case .photo(let mode):
            PhotoScreen(
                model: entry.model { PhotoModel(settings: container.settings, selection: container.photos) },
                onBack: { navigator.pop() },
                onRace: { navigator.replace(.lobby(mode)) },
                onSolo: { navigator.replace(.game(mode)) }
            )
        case .leaderboard:
            LeaderboardScreen(model: entry.model { LeaderboardModel(scores: container.scores) }, onBack: { navigator.pop() })
        case .game(let mode):
            GameScreen(
                model: entry.model {
                    GameModel(mode: mode, settings: container.settings, scores: container.scores, initialImage: container.photos.chosen?.image)
                },
                settings: container.settings,
                onBack: { navigator.pop() },
                onHome: { navigator.popToRoot() }
            )
        case .lobby(let mode):
            LobbyScreen(
                model: entry.model {
                    LobbyModel(mode: mode, settings: container.settings, hub: container.matchHub, initialPhoto: container.photos.chosen)
                },
                onBack: { navigator.pop() },
                onRaceStarting: { navigator.replace(.race) }
            )
        case .race:
            RaceRoute(hub: container.matchHub, settings: container.settings, navigator: navigator)
        }
    }
}

/// The race needs a live match; without one (e.g. it ended) it steps back.
private struct RaceRoute: View {
    @ObservedObject var hub: MatchHub
    let settings: SettingsRepository
    let navigator: Navigator

    var body: some View {
        if let controller = hub.controller {
            RaceGameScreen(controller: controller, settings: settings) {
                let mode = controller.state.config?.mode ?? .timeBased
                hub.end()
                navigator.replace(.lobby(mode))
            }
        } else {
            Color.clear.onAppear { navigator.pop() }
        }
    }
}
