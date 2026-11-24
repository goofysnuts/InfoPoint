import Foundation
import CryptoKit

enum AppError: LocalizedError {
    case http(Int, String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return msg.isEmpty ? "Fehler \(code)" : msg
        case .message(let msg): return msg
        }
    }

    // Server antwortet mit {"error": "..."}
    static func from(_ data: Data, code: Int) -> AppError {
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return .http(code, (obj?["error"] as? String) ?? "")
    }
}

// ── InfoPoint-Server (Docker-Container) ──────────────────────────────────────
final class ServerClient: NSObject, URLSessionDelegate {
    let baseURL: URL
    let allowSelfSigned: Bool
    private let username: String
    private let password: String

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 600
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.httpCookieAcceptPolicy = .always
        c.waitsForConnectivity = false
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    init(baseURL: URL, allowSelfSigned: Bool, username: String, password: String) {
        self.baseURL = baseURL
        self.allowSelfSigned = allowSelfSigned
        self.username = username
        self.password = password
    }

    func invalidate() { session.finishTasksAndInvalidate() }

    // selbst signiertes Zertifikat des Containers (Port 8791) nur für diesen Host akzeptieren
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           allowSelfSigned,
           challenge.protectionSpace.host == baseURL.host,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    private func url(_ path: String) -> URL {
        // Pfad mit Query ("api/geocode?q=…") nicht durch appendingPathComponent escapen lassen
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : baseURL.absoluteString + "/"
        return URL(string: base + path) ?? baseURL.appendingPathComponent(path)
    }

    private func send(_ path: String, method: String, json: [String: Any]?) async throws -> Data {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw AppError.from(data, code: code) }
        return data
    }

    func login() async throws {
        _ = try await send("api/auth/login", method: "POST", json: ["username": username, "password": password])
    }

    // Sitzung abgelaufen → einmal neu anmelden
    func request(_ path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
        do {
            return try await send(path, method: method, json: json)
        } catch AppError.http(401, _) {
            try await login()
            return try await send(path, method: method, json: json)
        }
    }

    func sync() async throws -> SyncData {
        let data = try await request("api/app/sync")
        return try JSONDecoder().decode(SyncData.self, from: data)
    }

    func report(_ p: PendingApply) async throws {
        var body: [String: Any] = [:]
        if let t = p.templateId { body["templateId"] = t }
        if let ui = p.ui { body["ui"] = ui.json.any }
        if let rev = p.rev { body["rev"] = rev }
        _ = try await request("api/app/devices/\(p.deviceId)/report", method: "POST", json: body)
    }

    // ── Vorlagen ────────────────────────────────────────────────────────────
    func createTemplate(name: String, firmware: String, members: [String]) async throws -> String {
        var body: [String: Any] = ["name": name, "firmware": firmware]
        if !members.isEmpty { body["app"] = ["members": members] }
        let data = try await request("api/templates", method: "POST", json: body)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = obj?["id"] as? String else { throw AppError.message("Vorlage konnte nicht angelegt werden") }
        return id
    }

    func updateTemplate(id: String, name: String, app: JSONValue) async throws {
        _ = try await request("api/templates/\(id)", method: "PUT", json: ["name": name, "app": app.any])
    }

    func deleteTemplate(id: String) async throws {
        _ = try await request("api/templates/\(id)", method: "DELETE")
    }

    // ── Suchen für den Vorlagen-Editor ──────────────────────────────────────
    private func getJSON(_ path: String) async throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try await request(path))
    }

    private static func q(_ s: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: safe) ?? ""
    }

    func geocode(_ text: String) async throws -> [JSONValue] {
        try await getJSON("api/geocode?q=\(Self.q(text))").arrayValue ?? []
    }

    func stops(_ text: String) async throws -> [JSONValue] {
        try await getJSON("api/stops?q=\(Self.q(text))").arrayValue ?? []
    }

    func teams(league: String) async throws -> [String] {
        let v = try await getJSON("api/teams?league=\(Self.q(league))")
        return (v["teams"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
    }

    func icloudCalendars() async throws -> [JSONValue] {
        let data = try await request("api/calendar/icloud", method: "POST", json: ["account": true])
        return try JSONDecoder().decode(JSONValue.self, from: data).arrayValue ?? []
    }

    // Firmware laden, Größe + MD5 prüfen, dann an ihren Platz legen
    func download(_ f: FirmwareInfo) async throws {
        var req = URLRequest(url: url(f.url))
        req.timeoutInterval = 120
        var (tmp, resp) = try await session.download(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            try await login()
            (tmp, resp) = try await session.download(for: req)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw AppError.http(code, "Download von \(f.name) fehlgeschlagen (\(code))") }
        let data = try Data(contentsOf: tmp, options: .mappedIfSafe)
        guard data.count == f.size else { throw AppError.message("\(f.name): Datei unvollständig") }
        if f.md5.count == 32 {
            let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard md5 == f.md5.lowercased() else { throw AppError.message("\(f.name): Prüfsumme stimmt nicht") }
        }
        let dest = Store.firmwareURL(f)
        try? FileManager.default.removeItem(at: dest)
        try data.write(to: dest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try? FileManager.default.removeItem(at: tmp)
    }
}

// ── Display im WLAN (lokale Schnittstelle der Firmware) ──────────────────────
struct DisplayClient {
    let base: URL

    private static let quick: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 4
        c.timeoutIntervalForResource = 10
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private static let slow: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 600
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    func info() async throws -> DisplayInfo {
        let (data, resp) = try await Self.quick.data(from: base.appendingPathComponent("info"))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppError.message("Display antwortet nicht – ältere Firmware ohne App-Schnittstelle?")
        }
        return try JSONDecoder().decode(DisplayInfo.self, from: data)
    }

    func sendConfig(_ body: Data, token: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent("config"))
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-Token")
        req.timeoutInterval = 15
        let (data, resp) = try await Self.slow.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw AppError.from(data, code: code) }
    }

    // Firmware als multipart/form-data hochladen (Feld "fw")
    func ota(file: URL, firmware f: FirmwareInfo, token: String,
             progress: @escaping @Sendable (Double) -> Void) async throws {
        let boundary = "InfoPoint-\(UUID().uuidString)"
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("ota-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: body) }

        FileManager.default.createFile(atPath: body.path, contents: nil)
        let out = try FileHandle(forWritingTo: body)
        out.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"fw\"; filename=\"firmware.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        out.write(try Data(contentsOf: file, options: .mappedIfSafe))
        out.write(Data("\r\n--\(boundary)--\r\n".utf8))
        try out.close()

        var req = URLRequest(url: base.appendingPathComponent("ota"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-Token")
        req.setValue(f.md5, forHTTPHeaderField: "X-MD5")
        req.setValue(String(f.size), forHTTPHeaderField: "X-Size")
        req.timeoutInterval = 90

        let delegate = UploadProgress(progress)
        let (data, resp) = try await Self.slow.upload(for: req, fromFile: body, delegate: delegate)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw AppError.from(data, code: code) }
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate {
    let callback: @Sendable (Double) -> Void
    init(_ cb: @escaping @Sendable (Double) -> Void) { callback = cb }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        callback(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
