import Foundation
import Security

// Ablage in Application Support – Firmwares, letzter Server-Stand, offene Meldungen
enum Store {
    static let base: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InfoPoint", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let firmwareDir: URL = {
        let url = base.appendingPathComponent("firmwares", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let previewDir: URL = {
        let url = base.appendingPathComponent("previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func clearPreviews() {
        try? FileManager.default.removeItem(at: previewDir)
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: base.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: base.appendingPathComponent(name),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: base.appendingPathComponent(name))
    }

    static func firmwareURL(_ f: FirmwareInfo) -> URL {
        firmwareDir.appendingPathComponent("\(f.id)-\(f.hash).bin")
    }

    static func hasFirmware(_ f: FirmwareInfo) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: firmwareURL(f).path)
        return (attrs?[.size] as? NSNumber)?.intValue == f.size
    }

    // ältere Stände derselben Firmware löschen, sobald der neue da ist
    static func pruneOlder(than f: FirmwareInfo) {
        let keep = firmwareURL(f).lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(atPath: firmwareDir.path)) ?? []
        for name in files where name.hasPrefix("\(f.id)-") && name != keep {
            try? FileManager.default.removeItem(at: firmwareDir.appendingPathComponent(name))
        }
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: base)
        try? FileManager.default.createDirectory(at: firmwareDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
    }
}

enum Keychain {
    private static let service = "de.infopoint.app"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func set(_ value: String, for account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var add = query(account)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
