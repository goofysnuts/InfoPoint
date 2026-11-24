import Foundation

// Beliebiges JSON (Gerätekonfiguration) – ganze Zahlen bleiben ganze Zahlen,
// sonst liest die Firmware z. B. "rot": 1.0 nicht als Integer.
enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

struct UserInfo: Codable, Hashable {
    var id: String
    var username: String
    var role: String
}

struct FirmwareInfo: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var multi: Bool
    var description: String?
    var version: String
    var hash: String
    var md5: String
    var size: Int
    var builtAt: String?
    var url: String
}

struct TemplateInfo: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var firmware: String
    var shared: Bool
    var mine: Bool
    var ownerName: String?
    var members: [String]
}

struct LastSeen: Codable, Hashable {
    var at: String
    var build: String?
    var ip: String?
    var fw: String?
    var rev: Int?
}

struct DeviceInfo: Codable, Identifiable {
    var id: String
    var name: String
    var firmware: String
    var templateId: String?
    var templateName: String?
    var rev: Int
    var token: String
    var tokenId: String
    var mine: Bool
    var ownerName: String?
    var online: Bool
    var lastSeen: LastSeen?
    var configs: [String: JSONValue]
}

struct SyncData: Codable {
    var serverTime: String
    var user: UserInfo
    var firmwares: [FirmwareInfo]
    var templates: [TemplateInfo]
    var devices: [DeviceInfo]
}

// Antwort des Displays auf GET /info
struct DisplayInfo: Codable, Equatable {
    var fw: String
    var name: String
    var ver: String
    var build: String
    var dev: String
    var cfgfw: String
    var rev: Int
    var ok: Bool
    var tid: String
    var mac: String
    var free: Int?
}

// Offline gesetzte Vorlage – wird dem Server nachgemeldet
struct PendingApply: Codable, Identifiable, Hashable {
    var id = UUID()
    var deviceId: String
    var templateId: String
    var rev: Int
    var createdAt = Date()
}
