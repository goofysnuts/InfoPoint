import Foundation
import Observation
import BackgroundTasks
import UIKit

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

    var serverURL: String { didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL"); resetClient() } }
    var username: String { didSet { UserDefaults.standard.set(username, forKey: "username"); resetClient() } }
    var allowSelfSigned: Bool { didSet { UserDefaults.standard.set(allowSelfSigned, forKey: "allowSelfSigned"); resetClient() } }
    var manualIPs: [String: String] { didSet { UserDefaults.standard.set(manualIPs, forKey: "manualIPs") } }
    var hasPassword: Bool

    let discovery = Discovery()

    @ObservationIgnored private var client: ServerClient?
    @ObservationIgnored private var previewCache: [String: UIImage] = [:]

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
    var online: Bool { serverReachable == true }

    // ── Server ──────────────────────────────────────────────────────────────
    private func resetClient() {
        client?.invalidate()
        client = nil
    }

    func api() -> ServerClient? {
        if let client { return client }
        guard let url = URL(string: serverURL), let pw = Keychain.get("password") else { return nil }
        let c = ServerClient(baseURL: url, allowSelfSigned: allowSelfSigned, username: username, password: pw)
        client = c
        return c
    }

    // Server-Aufruf für die Oberfläche: kein Server → verständlicher Fehler
    func withServer<T>(_ work: (ServerClient) async throws -> T) async throws -> T {
        guard let c = api() else { throw AppError.message("Nicht angemeldet") }
        do {
            let r = try await work(c)
            serverReachable = true
            return r
        } catch let e as URLError {
            serverReachable = false
            throw AppError.message("Server nicht erreichbar (\(e.localizedDescription))")
        }
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
        let name = user.trimmingCharacters(in: .whitespaces)
        let c = ServerClient(baseURL: url, allowSelfSigned: selfSigned, username: name, password: password)
        try await c.login()
        c.invalidate()
        Keychain.set(password, for: "password")
        hasPassword = true
        serverURL = s
        username = name
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
        UserDefaults.standard.removeObject(forKey: "lastSync")
    }

    // Abgleich: offene Meldungen nachreichen, Stand holen, neue Firmwares laden
    func syncNow() async {
        guard !syncing, let c = api() else { return }
        syncing = true
        defer { syncing = false }
        do {
            await replayPending(c)
            var s = try await c.sync()
            // neue Vorschaubilder auf dem Server → zwischengespeicherte verwerfen
            let pv = s.previewsVersion ?? 0
            if pv != UserDefaults.standard.double(forKey: "previewsVersion") {
                Store.clearPreviews()
                previewCache = [:]
                UserDefaults.standard.set(pv, forKey: "previewsVersion")
            }
            // noch nicht gemeldete Änderungen bleiben in der Anzeige sichtbar
            for p in pending { Self.overlay(p, on: &s) }
            data = s
            Store.save(s, "sync.json")
            serverReachable = true
            syncError = nil
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: "lastSync")
            await downloadFirmwares(c, s.firmwares)
        } catch {
            serverReachable = !(error is URLError)
            syncError = (error is URLError) ? nil : error.localizedDescription
        }
    }

    private func replayPending(_ c: ServerClient) async {
        for p in pending {
            do {
                try await c.report(p)
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
    var catalog: [CatalogEntry] { data?.catalog ?? [] }

    func device(_ id: String) -> DeviceInfo? { data?.devices.first { $0.id == id } }
    func template(_ id: String?) -> TemplateInfo? { data?.templates.first { $0.id == id } }
    func catalogEntry(_ id: String) -> CatalogEntry? { catalog.first { $0.id == id } }

    func firmwareName(_ id: String) -> String {
        catalogEntry(id)?.name ?? cached[id]?.name ?? data?.firmwares.first { $0.id == id }?.name ?? id
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

    // Konfiguration für ein Gerät mit Vorlage, aktueller Darstellung und Revision
    func configBody(device d: DeviceInfo, templateId: String, ui: UiSettings?, rev: Int) throws -> Data {
        guard case .object(var config)? = d.configs[templateId] else {
            throw AppError.message("Für dieses Gerät fehlt die Konfiguration. Ist ihm im Server ein WLAN zugeordnet? Danach einmal abgleichen.")
        }
        if let ui { config["ui"] = ui.json }
        config["rev"] = .int(rev)
        return try JSONEncoder().encode(config)
    }

    func nextRev(_ d: DeviceInfo, displayRev: Int) -> Int {
        max(d.rev, displayRev, d.lastSeen?.rev ?? 0) + 1
    }

    // Änderung lokal übernehmen und für den Server vormerken
    func record(_ p: PendingApply) {
        guard var s = data else { return }
        Self.overlay(p, on: &s)
        data = s
        Store.save(s, "sync.json")
        // ältere offene Meldungen desselben Geräts zusammenführen
        var merged = p
        for old in pending where old.deviceId == p.deviceId {
            if merged.templateId == nil { merged.templateId = old.templateId }
            if merged.ui == nil { merged.ui = old.ui }
        }
        pending.removeAll { $0.deviceId == p.deviceId }
        pending.append(merged)
        Store.save(pending, "pending.json")
    }

    private static func overlay(_ p: PendingApply, on s: inout SyncData) {
        guard let i = s.devices.firstIndex(where: { $0.id == p.deviceId }) else { return }
        if let tid = p.templateId, let t = s.templates.first(where: { $0.id == tid }) {
            s.devices[i].templateId = t.id
            s.devices[i].templateName = t.name
            s.devices[i].firmware = t.firmware
        }
        if let ui = p.ui { s.devices[i].ui = ui }
        if let rev = p.rev { s.devices[i].rev = max(s.devices[i].rev, rev) }
    }

    // Darstellung ändern: direkt ans Display, sonst über den Server
    enum UiResult { case display, server }

    func applyUi(_ ui: UiSettings, to d: DeviceInfo) async throws -> UiResult {
        if let tid = d.templateId, d.configs[tid] != nil, let reached = await reach(d) {
            let rev = nextRev(d, displayRev: reached.1.rev)
            let body = try configBody(device: d, templateId: tid, ui: ui, rev: rev)
            try await DisplayClient(base: reached.0).sendConfig(body, token: d.token)
            record(PendingApply(deviceId: d.id, templateId: nil, ui: ui, rev: rev))
            Task { await syncNow() }
            return .display
        }
        // Display nicht im WLAN: der Server gibt die Änderung beim nächsten Abruf weiter
        try await withServer { c in
            try await c.report(PendingApply(deviceId: d.id, templateId: nil, ui: ui, rev: nil))
        }
        record(PendingApply(deviceId: d.id, templateId: nil, ui: ui, rev: nil))
        pending.removeAll { $0.deviceId == d.id && $0.templateId == nil && $0.rev == nil }
        Store.save(pending, "pending.json")
        await syncNow()
        return .server
    }

    // ── Übersicht ───────────────────────────────────────────────────────────
    // online: im WLAN gefunden oder (bei erreichbarem Server) laut Server
    func isOnline(_ d: DeviceInfo) -> Bool {
        discovery.isVisible(tid: d.tokenId) || (online && d.online)
    }

    var wifi: [WifiInfo] { (data?.wifi ?? []).sorted { $0.name.localizedCompare($1.name) == .orderedAscending } }

    // Vorschaubild: Speicher → Datei → Server (nur die vier Einzel-Firmwares haben Bilder)
    static let previewFirmwares: Set<String> = ["bundesliga", "wetter", "kalender", "abfahrten"]

    func previewImage(_ name: String) async -> UIImage? {
        if let img = previewCache[name] { return img }
        let file = Store.previewDir.appendingPathComponent(name + ".png")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            previewCache[name] = img
            return img
        }
        guard let c = api(), let data = try? await c.preview(name), let img = UIImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        previewCache[name] = img
        return img
    }

    // ── WLAN (braucht den Server) ───────────────────────────────────────────
    func saveWifi(id: String?, name: String, ssid: String, password: String, clearPassword: Bool) async throws {
        try await withServer { try await $0.saveWifi(id: id, name: name, ssid: ssid, password: password, clearPassword: clearPassword) }
        await syncNow()
    }

    func deleteWifi(id: String) async throws {
        try await withServer { try await $0.deleteWifi(id: id) }
        await syncNow()
    }

    // ── Vorlagen (brauchen den Server) ──────────────────────────────────────
    func createTemplate(name: String, firmware: String, members: [String]) async throws -> String {
        let id = try await withServer { try await $0.createTemplate(name: name, firmware: firmware, members: members) }
        await syncNow()
        return id
    }

    func saveTemplate(id: String, name: String, app: JSONValue) async throws {
        try await withServer { try await $0.updateTemplate(id: id, name: name, app: app) }
        await syncNow()
    }

    func deleteTemplate(id: String) async throws {
        try await withServer { try await $0.deleteTemplate(id: id) }
        await syncNow()
    }
}
