import Foundation
import SwiftUI

// Beliebiges JSON (Gerätekonfiguration, Vorlagen) – ganze Zahlen bleiben ganze Zahlen,
// sonst liest die Firmware z. B. "rot": 1.0 nicht als Integer.
enum JSONValue: Codable, Equatable, Hashable {
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

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d.rounded())
        case .string(let s): return Int(s)
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    subscript(key: String) -> JSONValue? {
        get { objectValue?[key] }
        set {
            var o = objectValue ?? [:]
            o[key] = newValue
            self = .object(o)
        }
    }

    // für JSONSerialization
    var any: Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .object(let o): return o.mapValues { $0.any }
        case .array(let a): return a.map { $0.any }
        case .null: return NSNull()
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

// Feldbeschreibung aus firmwares.json – daraus entsteht der Vorlagen-Editor
struct FieldDef: Codable, Identifiable, Hashable {
    var id: String { key }
    var key: String
    var label: String
    var type: String
    var help: String?
    var min: Double?
    var max: Double?
    var options: [[String]]?
    var serverOnly: Bool?
    var `default`: JSONValue?
}

struct CatalogEntry: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var multi: Bool
    var description: String?
    var fields: [FieldDef]
}

struct TemplateInfo: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var firmware: String
    var shared: Bool
    var mine: Bool
    var ownerName: String?
    var canEdit: Bool?
    var members: [String]
    var app: JSONValue?
    var updatedAt: String?
}

struct LastSeen: Codable, Hashable {
    var at: String
    var build: String?
    var ip: String?
    var fw: String?
    var rev: Int?
}

// Darstellung am Display
struct UiSettings: Codable, Hashable {
    var palette: Int = 0
    var bright: Int = 100
    var dim: Int = 15
    var saver: Int = 60
    var smode: Int = 0      // 0 = Bildschirmschoner mit Uhr, 1 = nur dimmen
    var sfont: Int = 0      // Uhr-Schrift: 0 schlank, 1 kräftig, 2 technisch, 3 Digitaluhr
    var ssize: Int = 1      // 0 klein, 1 mittel, 2 groß
    var dfont: Int = 0      // Datum: 0 normal, 1 kräftig
    var dsize: Int = 0      // Datum: 0 klein, 1 mittel, 2 groß, 3 aus

    init() {}

    // ältere Stände ohne die neuen Felder lesen können
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        palette = try c.decodeIfPresent(Int.self, forKey: .palette) ?? 0
        bright = try c.decodeIfPresent(Int.self, forKey: .bright) ?? 100
        dim = try c.decodeIfPresent(Int.self, forKey: .dim) ?? 15
        saver = try c.decodeIfPresent(Int.self, forKey: .saver) ?? 60
        smode = try c.decodeIfPresent(Int.self, forKey: .smode) ?? 0
        sfont = try c.decodeIfPresent(Int.self, forKey: .sfont) ?? 0
        ssize = try c.decodeIfPresent(Int.self, forKey: .ssize) ?? 1
        dfont = try c.decodeIfPresent(Int.self, forKey: .dfont) ?? 0
        dsize = try c.decodeIfPresent(Int.self, forKey: .dsize) ?? 0
    }

    var json: JSONValue {
        .object(["palette": .int(palette), "bright": .int(bright), "dim": .int(dim), "saver": .int(saver),
                 "smode": .int(smode), "sfont": .int(sfont), "ssize": .int(ssize),
                 "dfont": .int(dfont), "dsize": .int(dsize)])
    }
}

enum ClockStyle {
    static let fonts: [(Int, String)] = [(0, "Schlank"), (1, "Kräftig"), (2, "Technisch"), (3, "Digitaluhr")]
    static let sizes: [(Int, String)] = [(0, "Klein"), (1, "Mittel"), (2, "Groß")]
    static let pixels: [CGFloat] = [64, 92, 128]
    static let dateFonts: [(Int, String)] = [(0, "Normal"), (1, "Kräftig")]
    static let dateSizes: [(Int, String)] = [(0, "Klein"), (1, "Mittel"), (2, "Groß"), (3, "Aus")]
    static let datePixels: [CGFloat] = [17, 22, 28]

    // Vorschau-Schrift, möglichst nah an der Display-Schrift
    static func font(_ style: Int, size: CGFloat) -> Font {
        switch style {
        case 1: return .system(size: size, weight: .bold).monospacedDigit()
        case 2: return .system(size: size, weight: .medium, design: .monospaced)
        case 3: return .custom("DSEG7 Classic", fixedSize: size).weight(.bold)
        default: return .system(size: size, weight: .light).monospacedDigit()
        }
    }
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
    var ui: UiSettings?
    var lastSeen: LastSeen?
    var configs: [String: JSONValue]
}

struct SyncData: Codable {
    var serverTime: String
    var user: UserInfo
    var firmwares: [FirmwareInfo]
    var templates: [TemplateInfo]
    var catalog: [CatalogEntry]?
    var icloudAccount: String?
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

// Offline gemachte Änderung – wird dem Server nachgemeldet
struct PendingApply: Codable, Identifiable, Hashable {
    var id = UUID()
    var deviceId: String
    var templateId: String?
    var ui: UiSettings?
    var rev: Int?
    var createdAt = Date()
}

// ── Designs (gleiche Reihenfolge wie Firmware und WebApp) ────────────────────
struct Palette: Identifiable {
    let id: Int
    let name: String
    let bg: Color
    let card: Color
    let accent: Color
    var light: Bool { id >= 11 }
    var shortName: String {
        name.replacingOccurrences(of: "Schwarz · ", with: "").replacingOccurrences(of: "Weiß · ", with: "")
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Palettes {
    private static let raw: [(String, UInt32, UInt32, UInt32)] = [
        ("Schwarz", 0x000000, 0x1C181C, 0x0A84FF), ("Nachtblau", 0x0A1C38, 0x12284C, 0x0A84FF),
        ("Petrol", 0x062A30, 0x0C3840, 0x0A84FF), ("Waldgrün", 0x0C2A18, 0x143822, 0x0A84FF),
        ("Weinrot", 0x300C18, 0x401424, 0x0A84FF), ("Violett", 0x1E1038, 0x2A1A4A, 0x0A84FF),
        ("Schwarz · Grün", 0x000000, 0x1C1C1E, 0x30D158), ("Schwarz · Orange", 0x000000, 0x1C1C1E, 0xFF9F0A),
        ("Schwarz · Rot", 0x000000, 0x1C1C1E, 0xFF453A), ("Schwarz · Violett", 0x000000, 0x1C1C1E, 0xBF5AF2),
        ("Schwarz · Türkis", 0x000000, 0x1C1C1E, 0x40C8E0),
        ("Weiß · Blau", 0xFFFFFF, 0xF2F2F7, 0x0040DD), ("Weiß · Grün", 0xFFFFFF, 0xF2F2F7, 0x248A3D),
        ("Weiß · Orange", 0xFFFFFF, 0xF2F2F7, 0xC93400), ("Weiß · Rot", 0xFFFFFF, 0xF2F2F7, 0xD70015),
        ("Weiß · Violett", 0xFFFFFF, 0xF2F2F7, 0x8944AB),
    ]

    static let all: [Palette] = raw.enumerated().map { item in
        Palette(id: item.offset, name: item.element.0, bg: Color(hex: item.element.1),
                card: Color(hex: item.element.2), accent: Color(hex: item.element.3))
    }

    static let groups: [(String, [Int])] = [
        ("Farbig", [0, 1, 2, 3, 4, 5]), ("Schwarz", [6, 7, 8, 9, 10]), ("Weiß", [11, 12, 13, 14, 15]),
    ]

    static func name(_ i: Int) -> String { all.indices.contains(i) ? all[i].name : "Design \(i)" }
}

enum SaverOptions {
    static let all: [(Int, String)] = [
        (0, "Aus"), (30, "30 Sekunden"), (60, "1 Minute"), (120, "2 Minuten"), (300, "5 Minuten"),
        (600, "10 Minuten"), (1800, "30 Minuten"), (3600, "1 Stunde"),
    ]
}

// Zeitplan der Mehrfach-Firmware
enum Schedule {
    static let days = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let rotations: [(Int, String)] = [
        (30, "30 Sekunden"), (60, "1 Minute"), (120, "2 Minuten"), (300, "5 Minuten"),
        (600, "10 Minuten"), (900, "15 Minuten"), (1800, "30 Minuten"), (3600, "1 Stunde"),
    ]
    static let colors: [String: Color] = [
        "bundesliga": Color(hex: 0xEF4444), "wetter": Color(hex: 0x0EA5E9),
        "kalender": Color(hex: 0xA855F7), "abfahrten": Color(hex: 0xF59E0B),
    ]

    static func hm(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func daysText(_ bits: Int) -> String {
        if bits == 127 { return "täglich" }
        if bits == 31 { return "Mo–Fr" }
        if bits == 96 { return "Sa–So" }
        return days.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element).joined(separator: ", ")
    }

    // gleiche Logik wie Display und WebApp: alle passenden Regeln, sonst Standard
    static func apps(rules: [JSONValue], def: String, members: [String], weekday wd: Int, minute: Int) -> [String] {
        var hits: [String] = []
        for r in rules {
            guard let a = r["a"]?.stringValue, members.contains(a), !hits.contains(a) else { continue }
            let d = r["d"]?.intValue ?? 127
            let f = r["f"]?.intValue ?? 0
            let t = r["t"]?.intValue ?? 0
            let today = d & (1 << wd) != 0
            let yesterday = d & (1 << ((wd + 6) % 7)) != 0
            let hit: Bool
            if f == t { hit = today }
            else if f < t { hit = today && minute >= f && minute < t }
            else { hit = (today && minute >= f) || (yesterday && minute < t) }
            if hit { hits.append(a) }
        }
        return hits.isEmpty ? [members.contains(def) ? def : (members.first ?? "")] : hits
    }
}
