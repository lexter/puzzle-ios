import Combine
import Foundation

/// App-wide owner of the current match, so it survives the Lobby → Race screen change.
/// Lives on the main actor; at most one connection at a time.
@MainActor
final class MatchHub: ObservableObject {
    @Published private(set) var controller: MatchController?
    /// The current controller's state, republished so views observing the hub update with it.
    @Published private(set) var match: MatchSnapshot?

    let discovery = Discovery()
    private var listener: PeerSockets.Listener?
    private var hostTask: Task<Void, Never>?
    private var matchSubscription: AnyCancellable?

    /// Opens a socket, advertises it, and accepts the first player who connects.
    func host(name: String, onError: @escaping (Error) -> Void) {
        end()
        hostTask = Task { [weak self] in
            guard let self else { return }
            do {
                let listener = try PeerSockets.Listener()
                self.listener = listener
                let port = try await listener.start()
                try Task.checkCancellation()
                self.discovery.advertise(name: name, port: Int(port))
                let connection = try await listener.accept()
                self.discovery.stopAdvertising()
                listener.close()
                self.listener = nil
                try Task.checkCancellation()
                self.setController(self.newController(role: .host, connection: connection, name: name))
            } catch is CancellationError {
                // end() was called.
            } catch {
                guard !Task.isCancelled else { return }
                onError(error)
            }
        }
    }

    func join(_ host: FoundHost, name: String) async throws {
        end()
        let connection = try await PeerSockets.connect(host: host.host, port: host.port)
        setController(newController(role: .guest, connection: connection, name: name))
    }

    /// Leaves any match, stops advertising and closes the listening socket.
    func end() {
        hostTask?.cancel()
        hostTask = nil
        discovery.stopAdvertising()
        listener?.close()
        listener = nil
        controller?.leave()
        setController(nil)
    }

    private func setController(_ controller: MatchController?) {
        matchSubscription = controller?.$state.sink { [weak self] in self?.match = $0 }
        if controller == nil { match = nil }
        self.controller = controller
    }

    private func newController(role: Role, connection: PeerConnection, name: String) -> MatchController {
        MatchController(
            role: role,
            connection: connection,
            myName: name,
            platform: platformName,
            now: monotonicMillis,
            validateImage: { PuzzleImage.prepare($0).isSuccess }
        )
    }
}
