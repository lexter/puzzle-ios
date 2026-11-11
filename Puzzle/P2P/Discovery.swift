import Foundation

/// A host advertising a match on the local network.
struct FoundHost: Equatable, Identifiable {
    let id: String
    let name: String
    let host: String
    let port: Int
}

/// Bonjour advertising and browsing for `serviceType`, via NetService on the main run loop.
@MainActor
final class Discovery {
    private static let domain = "local."
    private static let resolveTimeout: TimeInterval = 5

    private var published: NetService?

    func advertise(name: String, port: Int) {
        stopAdvertising()
        let service = NetService(domain: Self.domain, type: "\(serviceType).", name: name, port: Int32(port))
        service.publish()
        published = service
    }

    func stopAdvertising() {
        published?.stop()
        published = nil
    }

    /// Current list of hosts; browsing stops when iteration stops.
    func browse() -> AsyncStream<[FoundHost]> {
        AsyncStream { continuation in
            let session = BrowseSession { continuation.yield($0) }
            continuation.onTermination = { _ in
                Task { @MainActor in session.stop() }
            }
            continuation.yield([])
            session.start()
        }
    }
}

private final class BrowseSession: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var pending: [NetService] = []
    private var found: [(name: String, host: FoundHost)] = []
    private let publish: ([FoundHost]) -> Void

    init(publish: @escaping ([FoundHost]) -> Void) {
        self.publish = publish
    }

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "\(serviceType).", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        pending.forEach { $0.stop() }
        pending.removeAll()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        pending.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        pending.removeAll { $0 === service }
        if let index = found.firstIndex(where: { $0.name == service.name }) {
            found.remove(at: index)
            publish(found.map(\.host))
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = Self.ipv4(of: sender) ?? sender.hostName else { return }
        let entry = FoundHost(id: sender.name, name: sender.name, host: host, port: sender.port)
        if let index = found.firstIndex(where: { $0.name == sender.name }) {
            found[index] = (sender.name, entry)
        } else {
            found.append((sender.name, entry))
        }
        publish(found.map(\.host))
    }

    /// Hosts may listen on IPv4 only, but a `.local` name can resolve to IPv6 first, so dial the
    /// IPv4 address from the resolved sockaddrs (Darwin sockaddr_in: len, family, port, addr).
    private static func ipv4(of service: NetService) -> String? {
        for address in service.addresses ?? [] {
            let bytes = [UInt8](address)
            if bytes.count >= 8, Int32(bytes[1]) == AF_INET {
                return bytes[4...7].map(String.init).joined(separator: ".")
            }
        }
        return nil
    }
}
