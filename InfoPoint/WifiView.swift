import SwiftUI

struct WifiView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: WifiEditTarget?
    @State private var toDelete: WifiInfo?
    @State private var error: String?

    enum WifiEditTarget: Identifiable {
        case new
        case edit(WifiInfo)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let w): return w.id
            }
        }
    }

    var body: some View {
        NavigationStack {
            IPList {
                if !model.online {
                    Section {
                        Label("WLAN-Zugänge ändern geht nur, wenn der Server erreichbar ist.", systemImage: "icloud.slash")
                            .font(.dm(.footnote, 13))
                            .foregroundStyle(Theme.fg2)
                    }
                }
                Section {
                    ForEach(model.wifi) { w in
                        Button {
                            editing = .edit(w)
                        } label: {
                            HStack(spacing: 14) {
                                Tile(systemImage: "wifi", size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.name)
                                        .font(.dm(.body, 16, .bold))
                                        .foregroundStyle(Theme.fg)
                                    Text(w.ssid)
                                        .font(.dm(.subheadline, 14))
                                        .foregroundStyle(Theme.fg2)
                                }
                                Spacer()
                                Badge(text: w.hasPassword ? "geschützt" : "offen",
                                      color: w.hasPassword ? Theme.ok : Theme.warn,
                                      systemImage: w.hasPassword ? "lock.fill" : "lock.open")
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(!model.online)
                        .swipeActions {
                            if model.online {
                                Button(role: .destructive) { toDelete = w } label: { Label("Löschen", systemImage: "trash") }
                            }
                        }
                    }
                } footer: {
                    Text("Deine WLAN-Zugänge sind nur für dich sichtbar. Geräten ordnest du sie in der WebApp zu.")
                        .font(.dm(.footnote, 13))
                }
            }
            .overlay {
                if model.wifi.isEmpty {
                    ContentUnavailableView("Keine WLAN-Zugänge", systemImage: "wifi",
                                           description: Text("Lege mit + dein WLAN an."))
                }
            }
            .navigationTitle("WLAN")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel("WLAN hinzufügen")
                        .disabled(!model.online)
                }
            }
            .refreshable { await model.syncNow() }
            .sheet(item: $editing) { target in
                switch target {
                case .new: WifiEditor(existing: nil)
                case .edit(let w): WifiEditor(existing: w)
                }
            }
            .confirmationDialog("WLAN löschen?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible, presenting: toDelete) { w in
                Button("„\(w.name)“ löschen", role: .destructive) {
                    Task {
                        do { try await model.deleteWifi(id: w.id) } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .alert("Fehler", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }
}

// Anlegen/Bearbeiten – schlägt beim Anlegen das WLAN vor, in dem das iPhone gerade ist
private struct WifiEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: WifiInfo?

    @State private var name = ""
    @State private var ssid = ""
    @State private var password = ""
    @State private var clearPassword = false
    @State private var busy = false
    @State private var error: String?

    // Vorschlag
    @State private var suggestSsid: String?
    @State private var suggestVia: String?
    @State private var suggestSaved = false
    @State private var suggestChecked = false

    // Suche über ein Display
    @State private var scanning = false
    @State private var scanInfo: String?
    @State private var nets: [JSONValue] = []

    private var valid: Bool {
        let s = ssid.trimmingCharacters(in: .whitespaces)
        return !s.isEmpty && s.count <= 32 && (password.isEmpty || (8...63).contains(password.count))
    }

    var body: some View {
        NavigationStack {
            IPForm {
                if existing == nil {
                    Section {
                        if let suggestSsid {
                            HStack(spacing: 12) {
                                Image(systemName: suggestSaved ? "checkmark.circle.fill" : "wifi")
                                    .font(.title3)
                                    .foregroundStyle(suggestSaved ? Theme.ok : Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestSaved ? "Du bist gerade im WLAN \(suggestSsid) – das ist schon gespeichert."
                                                      : "Du bist gerade im WLAN \(suggestSsid)")
                                        .font(.dm(.subheadline, 14, .bold))
                                    if let via = suggestVia, !suggestSaved {
                                        Text("erkannt über \(via) im selben Netz")
                                            .font(.dm(.caption, 12))
                                            .foregroundStyle(Theme.fg2)
                                    }
                                }
                            }
                            .listRowBackground(Theme.accent.opacity(0.12))
                        } else if suggestChecked {
                            Label("Dein aktuelles WLAN konnte nicht erkannt werden (dazu muss ein Display im selben Netz sein).",
                                  systemImage: "info.circle")
                                .font(.dm(.footnote, 13))
                                .foregroundStyle(Theme.fg2)
                        } else {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Suche dein aktuelles WLAN …").font(.dm(.footnote, 13)).foregroundStyle(Theme.fg2)
                            }
                        }
                    }
                }

                Section("Netz") {
                    TextField("Name (z. B. Zuhause)", text: $name)
                    TextField("SSID", text: $ssid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    SecureField(existing?.hasPassword == true ? "unverändert lassen" : "Passwort", text: $password)
                        .disabled(clearPassword)
                    if existing?.hasPassword == true {
                        Toggle("Passwort entfernen (offenes Netz)", isOn: $clearPassword)
                    }
                } header: {
                    Text("Passwort")
                } footer: {
                    Text("8–63 Zeichen, leer für offene Netze.")
                }

                Section {
                    DisclosureGroup {
                        Button {
                            scan()
                        } label: {
                            HStack {
                                Text(scanning ? "Suche läuft …" : "Über meine Displays suchen")
                                Spacer()
                                if scanning { ProgressView() }
                            }
                        }
                        .disabled(scanning)
                        if let scanInfo {
                            Text(scanInfo).font(.dm(.caption, 12)).foregroundStyle(Theme.fg2)
                        }
                        ForEach(nets.indices, id: \.self) { i in
                            let n = nets[i]
                            let locked = n["e"]?.boolValue ?? ((n["e"]?.intValue ?? 1) != 0)
                            Button {
                                ssid = n["s"]?.stringValue ?? ""
                                if name.isEmpty { name = ssid }
                            } label: {
                                HStack {
                                    Image(systemName: locked ? "lock.fill" : "lock.open")
                                        .foregroundStyle(Theme.fg2)
                                    Text(n["s"]?.stringValue ?? "").foregroundStyle(Theme.fg)
                                    Spacer()
                                    Text("\(n["r"]?.intValue ?? 0) dBm")
                                        .font(.dm(.caption, 12).monospacedDigit())
                                        .foregroundStyle(Theme.fg2)
                                    if ssid == n["s"]?.stringValue {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Andere Netze suchen (über ein Display)", systemImage: "magnifyingglass")
                            .font(.dm(.body, 15, .bold))
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle(existing == nil ? "WLAN hinzufügen" : "WLAN bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Sichern", action: save).disabled(!valid) }
                }
            }
            .task {
                if let w = existing {
                    name = w.name
                    ssid = w.ssid
                } else {
                    await suggest()
                }
            }
        }
    }

    private func suggest() async {
        guard let c = model.api() else { suggestChecked = true; return }
        if let v = try? await c.wifiSuggest(), let s = v["ssid"]?.stringValue {
            suggestSsid = s
            suggestVia = v["via"]?.stringValue
            suggestSaved = v["savedId"]?.stringValue != nil
            if !suggestSaved {
                ssid = s   // direkt eintragen – nur noch das Passwort fehlt
                if name.isEmpty { name = s }
            }
        }
        suggestChecked = true
    }

    private func scan() {
        scanning = true
        scanInfo = nil
        nets = []
        Task {
            do {
                guard let c = model.api() else { throw AppError.message("Nicht angemeldet") }
                let since = Int(Date().timeIntervalSince1970 * 1000)
                let devices = try await c.startWifiScan()
                if devices.isEmpty { throw AppError.message("Gerade ist keins deiner Displays online.") }
                scanInfo = "Frage \(devices.joined(separator: ", ")) – dauert bis zu 20 s …"
                for _ in 0..<20 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    let r = try await c.wifiScanResults(since: since)
                    let list = r["nets"]?.arrayValue ?? []
                    let answered = r["pending"]?.boolValue == false && (r["at"]?.intValue ?? 0) > 0
                    if !list.isEmpty || answered {
                        nets = list
                        scanInfo = list.isEmpty ? "Das Display hat keine Netze gefunden." : "\(list.count) Netze gefunden."
                        break
                    }
                }
                if nets.isEmpty && scanInfo?.hasPrefix("Frage") == true { scanInfo = "Keine Antwort – ist das Display online?" }
            } catch {
                scanInfo = error.localizedDescription
            }
            scanning = false
        }
    }

    private func save() {
        busy = true
        error = nil
        Task {
            do {
                let s = ssid.trimmingCharacters(in: .whitespaces)
                try await model.saveWifi(id: existing?.id, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? s : name,
                                         ssid: s, password: password, clearPassword: clearPassword)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
