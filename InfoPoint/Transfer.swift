import Foundation
import Observation

// Vorlage auf ein Display bringen – komplett ohne Server:
// 1. Display im WLAN finden  2. ggf. Firmware hochladen und Neustart abwarten
// 3. Einstellungen senden  4. dem Server nachmelden (sofort oder sobald er erreichbar ist)
@MainActor
@Observable
final class TransferJob: Identifiable {
    let id = UUID()
    enum Step: Int, CaseIterable {
        case connect, firmware, restart, config, done

        var title: String {
            switch self {
            case .connect: return "Display verbinden"
            case .firmware: return "Firmware übertragen"
            case .restart: return "Neustart abwarten"
            case .config: return "Einstellungen senden"
            case .done: return "Fertig"
            }
        }
    }

    let deviceName: String
    let templateName: String
    var step: Step = .connect
    var uploadProgress: Double = 0
    var firmwareNeeded = true
    var error: String?
    var finished = false
    var running = false

    init(deviceName: String, templateName: String) {
        self.deviceName = deviceName
        self.templateName = templateName
    }

    func run(model: AppModel, device: DeviceInfo, template t: TemplateInfo, forceFirmware: Bool) async {
        running = true
        error = nil
        defer { running = false }
        do {
            guard let fw = model.cached[t.firmware] else {
                throw AppError.message("Die Firmware „\(model.firmwareName(t.firmware))“ liegt noch nicht in der App. Einmal mit dem Server abgleichen.")
            }
            guard device.configs[t.id] != nil else {
                throw AppError.message("Für dieses Gerät fehlt die Konfiguration. Ist ihm im Server ein WLAN zugeordnet? Danach einmal abgleichen.")
            }

            step = .connect
            guard let reached = await model.reach(device) else {
                throw AppError.message("Display nicht im WLAN gefunden. Ist es eingeschaltet, im selben WLAN und hat schon die Firmware mit App-Schnittstelle? Notfalls die IP-Adresse eintragen.")
            }

            var base = reached.0
            var current = reached.1
            let info = current
            firmwareNeeded = forceFirmware || info.fw != fw.id || info.build != fw.hash
            if firmwareNeeded {
                step = .firmware
                uploadProgress = 0
                try await DisplayClient(base: base).ota(file: Store.firmwareURL(fw), firmware: fw, token: device.token) { p in
                    Task { @MainActor in self.uploadProgress = p }
                }
                uploadProgress = 1
                step = .restart
                (base, current) = try await waitForRestart(model: model, device: device, fallback: base, build: fw.hash)
            }

            step = .config
            let rev = model.nextRev(device, displayRev: current.rev)
            let body = try model.configBody(device: device, templateId: t.id, ui: device.ui, rev: rev)
            try await DisplayClient(base: base).sendConfig(body, token: device.token)

            model.record(PendingApply(deviceId: device.id, templateId: t.id, ui: nil, rev: rev))
            step = .done
            finished = true
            Task { await model.syncNow() }   // dem Server melden, falls er erreichbar ist
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func waitForRestart(model: AppModel, device: DeviceInfo, fallback: URL, build: String) async throws -> (URL, DisplayInfo) {
        try await Task.sleep(nanoseconds: 4_000_000_000)
        for _ in 0..<45 {
            var urls = model.candidateURLs(for: device)
            if !urls.contains(fallback) { urls.insert(fallback, at: 0) }
            for u in urls {
                if let i = try? await DisplayClient(base: u).info(), i.tid == device.tokenId {
                    guard i.build == build else {
                        throw AppError.message("Das Display läuft wieder, aber mit der alten Firmware – das Update wurde nicht übernommen.")
                    }
                    return (u, i)
                }
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw AppError.message("Das Display meldet sich nach dem Update nicht zurück. Prüfe, ob es wieder im WLAN ist, und versuche es erneut.")
    }
}
