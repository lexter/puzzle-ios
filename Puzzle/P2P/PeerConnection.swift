import Foundation
import Network

/// A connected peer. `incoming` finishes when the connection ends.
@MainActor
protocol PeerConnection: AnyObject {
    var incoming: AsyncStream<Frame> { get }
    var isClosed: Bool { get }
    /// Queues `frame`; frames go out in the order they're sent.
    func send(_ frame: Frame)
    /// Sends `frame` and waits until it has been handed to the network (or the link failed).
    func sendAndWait(_ frame: Frame) async
    func close()
}

/// `PeerConnection` over a Network.framework TCP connection (run on the main queue); callbacks
/// are hopped onto the main actor.
@MainActor
final class NetworkPeerConnection: PeerConnection {
    private static let readChunk = 16 * 1024

    private let connection: NWConnection
    private let decoder = Framing.Decoder()
    private var continuation: AsyncStream<Frame>.Continuation?
    let incoming: AsyncStream<Frame>
    private(set) var isClosed = false

    /// `connection` must already be in the `.ready` state.
    init(connection: NWConnection) {
        self.connection = connection
        var captured: AsyncStream<Frame>.Continuation?
        incoming = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in self?.close() }
            default:
                break
            }
        }
        receiveNext()
    }

    private nonisolated func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.readChunk) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty {
                    do {
                        for raw in try self.decoder.feed(data) {
                            if let frame = MatchCodec.fromRaw(raw) { self.continuation?.yield(frame) }
                        }
                    } catch {
                        // Malformed stream: treated as a disconnect.
                        self.close()
                        return
                    }
                }
                if isComplete || error != nil {
                    self.close()
                } else {
                    self.receiveNext()
                }
            }
        }
    }

    func send(_ frame: Frame) {
        guard !isClosed, let bytes = try? MatchCodec.encode(frame) else { return }
        connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.close() }
        })
    }

    func sendAndWait(_ frame: Frame) async {
        guard !isClosed, let bytes = try? MatchCodec.encode(frame) else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            connection.send(content: bytes, completion: .contentProcessed { _ in done.resume() })
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        continuation?.finish()
        continuation = nil
        connection.cancel()
    }
}

struct PeerConnectError: Error {}

/// Opening, accepting and dialing LAN TCP sockets.
@MainActor
enum PeerSockets {
    private static let connectTimeout: TimeInterval = 10

    /// A listening socket on a system-chosen port that hands over the first player who connects.
    @MainActor
    final class Listener {
        private let listener: NWListener
        private var accepted: NWConnection?
        private var waiting: CheckedContinuation<NWConnection, Error>?
        private var ready: CheckedContinuation<UInt16, Error>?
        private var closed = false

        init() throws {
            listener = try NWListener(using: .tcp, on: .any)
        }

        /// Starts listening and returns the port once the socket is bound.
        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.offer(connection) }
            }
            return try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in self?.onState(state) }
                }
                listener.start(queue: .main)
            }
        }

        /// Waits for the first player to connect; throws `CancellationError` if closed first.
        func accept() async throws -> PeerConnection {
            let connection = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWConnection, Error>) in
                if closed { return continuation.resume(throwing: CancellationError()) }
                if let pending = accepted {
                    accepted = nil
                    return continuation.resume(returning: pending)
                }
                waiting = continuation
            }
            try await PeerSockets.waitUntilReady(connection)
            return NetworkPeerConnection(connection: connection)
        }

        func close() {
            guard !closed else { return }
            closed = true
            listener.cancel()
            accepted?.cancel()
            accepted = nil
            waiting?.resume(throwing: CancellationError())
            waiting = nil
            ready?.resume(throwing: CancellationError())
            ready = nil
        }

        private func onState(_ state: NWListener.State) {
            switch state {
            case .ready:
                ready?.resume(returning: listener.port?.rawValue ?? 0)
                ready = nil
            case .failed(let error):
                ready?.resume(throwing: error)
                ready = nil
                waiting?.resume(throwing: error)
                waiting = nil
            default:
                break
            }
        }

        private func offer(_ connection: NWConnection) {
            guard !closed else { return connection.cancel() }
            if let waiting {
                self.waiting = nil
                waiting.resume(returning: connection)
            } else if accepted == nil {
                accepted = connection
            } else {
                connection.cancel()
            }
        }
    }

    static func connect(host: String, port: Int) async throws -> PeerConnection {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { throw PeerConnectError() }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        try await waitUntilReady(connection)
        return NetworkPeerConnection(connection: connection)
    }

    /// Starts `connection` and waits for `.ready`; a connection that can't get there (or stalls
    /// in `.waiting`) is cancelled and reported as an error.
    fileprivate static func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            @Sendable func finish(_ result: Result<Void, Error>) {
                guard once.claim() else { return }
                connection.stateUpdateHandler = nil
                if case .failure = result { connection.cancel() }
                continuation.resume(with: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .waiting(let error), .failed(let error): finish(.failure(error))
                case .cancelled: finish(.failure(CancellationError()))
                default: break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeout) { finish(.failure(PeerConnectError())) }
        }
    }
}

/// Lets exactly one of several racing callbacks (all on the main queue) win.
private final class Once: @unchecked Sendable {
    private var done = false

    func claim() -> Bool {
        guard !done else { return false }
        done = true
        return true
    }
}
