import Foundation
import Network
import Observation

// Findet Displays im WLAN über Bonjour (_infopoint._tcp). Im TXT-Eintrag steht "tid":
// eine Kennung des Geräte-Tokens – so ordnet die App das Display dem Gerät zu.
@MainActor
@Observable
final class Discovery {
    struct Found: Identifiable, Hashable {
        var id: String { name }
        let name: String
        var tid: String
        var fw: String
        var url: URL?
    }

    private(set) var found: [String: Found] = [:]
    private(set) var running = false

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var resolving: Set<String> = []

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_infopoint._tcp", domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.update(results) }
        }
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.running = true
                case .failed, .cancelled: self?.running = false
                default: break
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        running = false
    }

    func restart() {
        stop()
        found = [:]
        resolving = []
        start()
    }

    func url(forTid tid: String) -> URL? {
        guard !tid.isEmpty else { return nil }
        return found.values.first { $0.tid == tid && $0.url != nil }?.url
    }

    func isVisible(tid: String) -> Bool {
        !tid.isEmpty && found.values.contains { $0.tid == tid }
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var next: [String: Found] = [:]
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint else { continue }
            var tid = "", fw = ""
            if case let .bonjour(txt) = r.metadata {
                tid = txt["tid"] ?? ""
                fw = txt["fw"] ?? ""
            }
            var f = found[name] ?? Found(name: name, tid: tid, fw: fw, url: nil)
            f.tid = tid
            f.fw = fw
            next[name] = f
            if f.url == nil { resolve(r.endpoint, name: name) }
        }
        found = next
    }

    // Dienst auflösen: kurz verbinden und die IPv4-Adresse des Displays ablesen
    private func resolve(_ endpoint: NWEndpoint, name: String) {
        guard !resolving.contains(name) else { return }
        resolving.insert(name)
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let conn = NWConnection(to: endpoint, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                var url: URL?
                if case let .hostPort(host, port) = conn.currentPath?.remoteEndpoint {
                    var h = "\(host)"
                    if let i = h.firstIndex(of: "%") { h = String(h[..<i]) }
                    url = URL(string: "http://\(h):\(port.rawValue)")
                }
                conn.cancel()
                Task { @MainActor in
                    self?.resolving.remove(name)
                    if let url { self?.found[name]?.url = url }
                }
            case .failed, .waiting:
                conn.cancel()
                Task { @MainActor in self?.resolving.remove(name) }
            default:
                break
            }
        }
        conn.start(queue: .main)
    }
}
