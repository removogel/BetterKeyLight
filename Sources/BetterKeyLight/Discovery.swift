import Foundation
import Network

/// A Key Light found on the local network via Bonjour.
struct DiscoveredLight: Identifiable, Equatable {
    var name: String
    var host: String
    var port: Int
    var id: String { name }
}

/// Browses for Elgato lights (`_elg._tcp`) and resolves them to an IPv4 address.
@MainActor
final class Discovery {
    var onChange: (@MainActor ([DiscoveredLight]) -> Void)?

    private(set) var lights: [DiscoveredLight] = [] {
        didSet { if lights != oldValue { onChange?(lights) } }
    }

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]

    func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: "_elg._tcp", domain: nil), using: NWParameters())
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.update(results) }
        }
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.browserState(state) }
        }
        browser = b
        b.start(queue: .main)
    }

    private func browserState(_ state: NWBrowser.State) {
        guard case .failed = state else { return }
        browser?.cancel()
        browser = nil
        Task {
            try? await Task.sleep(for: .seconds(5))
            start()
        }
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var names = Set<String>()
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            names.insert(name)
            let known = lights.contains { $0.name == name }
            if !known && resolvers[name] == nil {
                resolve(name: name, endpoint: result.endpoint)
            }
        }
        lights.removeAll { !names.contains($0.name) }
        for name in Array(resolvers.keys) where !names.contains(name) {
            resolvers.removeValue(forKey: name)?.cancel()
        }
    }

    /// Opens a short-lived connection to learn the service's address and port.
    private func resolve(name: String, endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let conn = NWConnection(to: endpoint, using: params)
        resolvers[name] = conn
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            let c = conn
            switch state {
            case .ready:
                let remote = c?.currentPath?.remoteEndpoint
                Task { @MainActor in self?.finish(name: name, connection: c, endpoint: remote) }
            case .failed, .cancelled:
                Task { @MainActor in self?.finish(name: name, connection: c, endpoint: nil) }
            default:
                break
            }
        }
        conn.start(queue: .main)
        Task {
            try? await Task.sleep(for: .seconds(5))
            if let current = resolvers[name], current === conn { current.cancel() }
        }
    }

    private func finish(name: String, connection: NWConnection?, endpoint: NWEndpoint?) {
        if let connection, let current = resolvers[name], current === connection {
            resolvers.removeValue(forKey: name)
            connection.cancel()
        }
        guard let endpoint, case let .hostPort(host, port) = endpoint else { return }
        let address: String
        switch host {
        case .ipv4(let a): address = "\(a)"
        case .ipv6(let a): address = "\(a)"
        case .name(let n, _): address = n
        @unknown default: return
        }
        // Strip an interface suffix such as "%en0".
        let clean = address.split(separator: "%").first.map(String.init) ?? address
        guard !clean.isEmpty else { return }
        var list = lights.filter { $0.name != name }
        list.append(DiscoveredLight(name: name, host: clean, port: Int(port.rawValue)))
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lights = list
    }
}
