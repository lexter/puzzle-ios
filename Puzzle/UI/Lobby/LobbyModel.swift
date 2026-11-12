import CoreGraphics
import Combine
import Foundation

enum LobbyTab { case host, join }

let noHostsHintMs: Int64 = 10_000

/// Host or join a race on the local network, and set the hosted match up.
@MainActor
final class LobbyModel: ObservableObject, ScreenModel {
    @Published private(set) var tab = LobbyTab.host
    @Published private(set) var myName = ""
    @Published private(set) var grid: Int
    let mode: Mode
    @Published private(set) var customImage: CGImage?
    @Published private(set) var customJpeg: Data?
    @Published private(set) var hosts: [FoundHost] = []
    @Published private(set) var noHostsHint = false
    @Published private(set) var joining: String?
    @Published private(set) var error: String?
    @Published private(set) var message: UserMessage?

    let hub: MatchHub
    private let settings: SettingsStore
    private var browseTask: Task<Void, Never>?
    private var handedOff = false
    private var hubSubscription: AnyCancellable?
    private(set) lazy var picker = ImagePicker { [weak self] in self?.setPicture($0) }

    init(mode: Mode, settings: SettingsStore, hub: MatchHub, defaultName: () -> String = DefaultPlayerName.get, initialPhoto: ChosenPhoto? = nil) {
        self.mode = mode
        self.settings = settings
        self.hub = hub
        customImage = initialPhoto?.image
        customJpeg = initialPhoto?.jpeg
        grid = settings.gridSize
        let saved = settings.playerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        myName = saved.flatMap { $0.isEmpty ? nil : settings.playerName } ?? defaultName()
        // Views observe this model; forward hub changes (the match) to them.
        hubSubscription = hub.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        // Start hosting after the screen is built, not while SwiftUI is creating it.
        Task { [weak self] in self?.selectTab(.host) }
    }

    var match: MatchSnapshot? { hub.match }

    func selectTab(_ tab: LobbyTab) {
        self.tab = tab
        error = nil
        hosts = []
        noHostsHint = false
        joining = nil
        browseTask?.cancel()
        switch tab {
        case .host:
            hub.host(name: myName) { [weak self] error in
                self?.error = "Couldn't start hosting (\(error.localizedDescription)). Check Wi-Fi."
            }
        case .join:
            hub.end()
            let stream = hub.discovery.browse()
            browseTask = Task { [weak self] in
                let hint = Task { [weak self] in
                    await sleep(ms: noHostsHintMs)
                    guard !Task.isCancelled, let self, self.hosts.isEmpty else { return }
                    self.noHostsHint = true
                }
                defer { hint.cancel() }
                for await found in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.hosts = found
                    self.noHostsHint = self.noHostsHint && found.isEmpty
                }
            }
        }
    }

    func retry() { selectTab(tab) }

    /// The other player left or the link dropped while still in the lobby: start over.
    func onMatchLost() {
        selectTab(tab)
        error = "The other player left. You can host or join again."
    }

    func join(_ host: FoundHost) {
        joining = host.name
        error = nil
        Task {
            do {
                browseTask?.cancel()
                try await hub.join(host, name: myName)
            } catch {
                joining = nil
                self.error = "Couldn't connect to \(host.name). Are you on the same Wi-Fi?"
            }
        }
    }

    /// Host accepts the waiting player: sends grid, mode and picture.
    func accept() { hub.controller?.configure(grid: grid, mode: mode, imageBytes: customJpeg) }

    /// Host turns the joining player away and keeps hosting.
    func decline() { selectTab(.host) }

    func startRace() { hub.controller?.startRace() }

    func setGrid(_ size: Int) {
        let clamped = size.clamped(to: PuzzleState.minSize...PuzzleState.maxSize)
        grid = clamped
        settings.setGridSize(clamped)
    }

    func setPicture(_ result: PickResult) {
        switch result {
        case .cancelled: break
        case .permissionDenied: message = .cameraDenied
        case .picked(let bytes):
            Task {
                switch await preparePhoto(bytes) {
                case .success(let photo):
                    customImage = photo.image
                    customJpeg = photo.jpeg
                case .failure(let error):
                    message = .from(error)
                }
            }
        }
    }

    func useScenic() {
        customImage = nil
        customJpeg = nil
    }

    func dismissMessage() { message = nil }

    /// Called when navigating to the race so the match isn't torn down with this screen.
    func handOff() { handedOff = true }

    func onCleared() {
        browseTask?.cancel()
        if !handedOff { hub.end() }
    }
}
