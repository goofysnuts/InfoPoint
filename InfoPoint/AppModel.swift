import Foundation
import Observation
import BackgroundTasks

let refreshTaskId = "de.infopoint.app.sync"

@MainActor
@Observable
final class AppModel {

    // letzter Stand vom Server (bleibt offline verfügbar)
    var data: SyncData?
    // Firmwares, die tatsächlich in der App liegen (id → Stand)
    var cached: [String: FirmwareInfo] = [:]
    var pending: [PendingApply] = []
    var downloading: Set<String> = []

    var lastSync: Date?
    var serverReachable: Bool?
    var syncing = false
    var syncError: String?

    var serverURL: String { didSet { defaults.set(serverURL, forKey: "serverURL"); resetClient() } }
    var username: String { didSet { defaults.set(username, forKey: "username"); resetClient() } }
    var allowSelfSigned: Bool { didSet { defaults.set(allowSelfSigned, forKey: "allowSelfSigned"); resetClient() } }
    var manualIPs: [String: String] { didSet { defaults.set(manualIPs, forKey: "manualIPs") } }
    var hasPassword: Bool

    let discovery = Discovery()

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var client: ServerClient?

    init() {
        let d = UserDefaults.standard
        serverURL = d.string(forKey: "serverURL") ?? ""
        username = d.string(forKey: "username") ?? ""
        allowSelfSigned = d.bool(forKey: "allowSelfSigned")
        manualIPs = (d.dictionary(forKey: "manualIPs") as? [String: String]) ?? [:]
        hasPassword = Keychain.get("password") != nil
        lastSync = d.object(forKey: "lastSync") as? Date
        data = Store.load(SyncData.self, "sync.json")
        pending = Store.load([PendingApply].self, "pending.json") ?? []
        let list = Store.load([FirmwareInfo].self, "firmwares.json") ?? []
        cached = Dictionary(list.filter(Store.hasFirmware).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var isLoggedIn: Bool { !serverURL.isEmpty && !username.isEmpty && hasPassword }

    // ── Server ──────────────────────────────────────────────────────────────
    private func resetClient() {
        client?.invalidate()
        client = nil
    }

    private func currentClient() -> ServerClient? {
        if let client { return client }
        guard let url = URL(string: serverURL), let pw = Keychain.get("password") else { return nil }
        let c = ServerClient(baseURL: url, allowSelfSigned: allowSelfSigned, username: username, password: pw)
        client = c
        return c
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty && !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func login(server: String, user: String, password: String, selfSigned: Bool) async throws {
        let s = Self.normalize(server)
        guard let url = URL(string: s), url.host != nil else { throw AppError.message("Server-Adresse ungültig") }
        let c = ServerClient(baseURL: url, allowSelfSigned: selfSigned,
                             username: user.trimmingCharacters(in: .whitespaces), password: password)
        try await c.login()
        c.invalidate()
        Keychain.set(password, for: "password")
        hasPassword = true
        serverURL = s
        username = user.trimmingCharacters(in: .whitespaces)
        allowSelfSigned = selfSigned
        await syncNow()
    }

    func logout() {
        Keychain.delete("password")
        hasPassword = false
        resetClient()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        data = nil
        cached = [:]
        pending = []
        lastSync = nil
        serverReachable = nil
        Store.wipe()
        defaults.removeObject(forKey: "lastSync")
    }

    // Abgleich: offene Meldungen nachreichen, Stand holen, neue Firmwares laden
    func syncNow() async {
        guard !syncing, let c = currentClient() else { return }
        syncing = true
        defer { syncing = false }
        do {
            await replayPending(c)
            let s = try await c.sync()
            data = s
            Store.save(s, "sync.json")
            serverReachable = true
            syncError = nil
            lastSync = Date()
            defaults.set(lastSync, forKey: "lastSync")
            await downloadFirmwares(c, s.firmwares)
        } catch {
            serverReachable = !(error is URLError)
            syncError = (error is URLError) ? nil : error.localizedDescription
        }
    }

    private func replayPending(_ c: ServerClient) async {
        for p in pending {
            do {
                try await c.reportApply(p)
                pending.removeAll { $0.id == p.id }
            } catch AppError.http(let code, _) where (400..<500).contains(code) && code != 401 {
                pending.removeAll { $0.id == p.id }   // Gerät/Vorlage gibt es nicht mehr
            } catch {
                break
            }
        }
        Store.save(pending, "pending.json")
    }

    private func downloadFirmwares(_ c: ServerClient, _ list: [FirmwareInfo]) async {
        for f in list {
            if Store.hasFirmware(f) {
                cached[f.id] = f
                continue
            }
            downloading.insert(f.id)
            do {
                try await c.download(f)
                cached[f.id] = f
                Store.pruneOlder(than: f)
            } catch {
                syncError = error.localizedDescription
            }
            downloading.remove(f.id)
            Store.save(Array(cached.values), "firmwares.json")
        }
        Store.save(Array(cached.values), "firmwares.json")
    }

    // ── Hintergrund-Abgleich ────────────────────────────────────────────────
    nonisolated static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }

    // ── Hilfen für die Oberfläche ──────────────────────────────────────────
    var devices: [DeviceInfo] { (data?.devices ?? []).sorted { $0.name.localizedCompare($1.name) == .orderedAscending } }
    var templates: [TemplateInfo] { (data?.templates ?? []).sorted { $0.name.localizedCompare($1.name) == .orderedAscending } }

    func device(_ id: String) -> DeviceInfo? { data?.devices.first { $0.id == id } }
    func template(_ id: String?) -> TemplateInfo? { data?.templates.first { $0.id == id } }

    func firmwareName(_ id: String) -> String {
        cached[id]?.name ?? data?.firmwares.first { $0.id == id }?.name ?? id
    }

    func pendingCount(for deviceId: String) -> Int { pending.filter { $0.deviceId == deviceId }.count }

    // mögliche Adressen eines Displays: Bonjour, manuell, zuletzt vom Server gemeldet
    func candidateURLs(for d: DeviceInfo) -> [URL] {
        var urls: [URL] = []
        if let u = discovery.url(forTid: d.tokenId) { urls.append(u) }
        if let ip = manualIPs[d.id], !ip.isEmpty, let u = URL(string: "http://\(ip)") { urls.append(u) }
        if let ip = d.lastSeen?.ip, !ip.isEmpty, let u = URL(string: "http://\(ip)") { urls.append(u) }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    // erstes Display, das antwortet und zum Gerät gehört
    func reach(_ d: DeviceInfo) async -> (URL, DisplayInfo)? {
        for url in candidateURLs(for: d) {
            if let info = try? await DisplayClient(base: url).info(), info.tid == d.tokenId {
                return (url, info)
            }
        }
        return nil
    }

    // nach einer Übertragung den lokalen Stand anpassen (bis der Server bestätigt)
    func noteApplied(deviceId: String, template t: TemplateInfo, rev: Int) {
        guard var s = data, let i = s.devices.firstIndex(where: { $0.id == deviceId }) else { return }
        s.devices[i].templateId = t.id
        s.devices[i].templateName = t.name
        s.devices[i].firmware = t.firmware
        s.devices[i].rev = rev
        data = s
        Store.save(s, "sync.json")
        pending.removeAll { $0.deviceId == deviceId }
        pending.append(PendingApply(deviceId: deviceId, templateId: t.id, rev: rev))
        Store.save(pending, "pending.json")
    }
}
