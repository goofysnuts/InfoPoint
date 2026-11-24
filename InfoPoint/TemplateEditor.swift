import SwiftUI

// ── Bindings in JSON hinein ─────────────────────────────────────────────────
extension Binding where Value == JSONValue {
    func field(_ key: String) -> Binding<JSONValue> {
        Binding<JSONValue>(
            get: { self.wrappedValue[key] ?? .null },
            set: { newValue in
                var v = self.wrappedValue
                v[key] = newValue
                self.wrappedValue = v
            })
    }

    var string: Binding<String> {
        Binding<String>(get: { self.wrappedValue.stringValue ?? "" }, set: { self.wrappedValue = .string($0) })
    }

    var int: Binding<Int> {
        Binding<Int>(get: { self.wrappedValue.intValue ?? 0 }, set: { self.wrappedValue = .int($0) })
    }

    var bool: Binding<Bool> {
        Binding<Bool>(get: { self.wrappedValue.boolValue ?? false }, set: { self.wrappedValue = .bool($0) })
    }

    var array: Binding<[JSONValue]> {
        Binding<[JSONValue]>(get: { self.wrappedValue.arrayValue ?? [] }, set: { self.wrappedValue = .array($0) })
    }
}

// ── Editor ──────────────────────────────────────────────────────────────────
struct TemplateEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let templateId: String

    @State private var name = ""
    @State private var app: JSONValue = .object([:])
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?

    private var template: TemplateInfo? { model.template(templateId) }
    private var editable: Bool { (template?.canEdit ?? false) && model.online }
    private var dirty: Bool {
        guard let t = template else { return false }
        return name != t.name || app != (t.app ?? .object([:]))
    }

    var body: some View {
        if let t = template {
            IPForm {
                if !model.online {
                    Section {
                        Label("Bearbeiten geht nur mit Verbindung zum Server.", systemImage: "icloud.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if t.canEdit != true {
                    Section {
                        Label("Vorlage des Admins – nur ansehen.", systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Name") {
                    TextField("Name", text: $name)
                        .disabled(!editable)
                }

                if model.catalogEntry(t.firmware)?.multi == true {
                    MultiEditor(app: $app, editable: editable)
                } else if let entry = model.catalogEntry(t.firmware) {
                    Section {
                        FieldsList(fields: entry.fields, value: $app, editable: editable)
                    } header: {
                        Label(entry.name, systemImage: FirmwareStyle.symbol(entry.id))
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(t.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else if editable {
                        Button("Sichern", action: save).disabled(!dirty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                name = t.name
                app = t.app ?? .object([:])
                loaded = true
            }
        } else {
            ContentUnavailableView("Vorlage nicht gefunden", systemImage: "square.grid.2x2")
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                try await model.saveTemplate(id: templateId, name: name.trimmingCharacters(in: .whitespaces), app: app)
                dismiss()   // zurück zur Übersicht
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}

// ── Felder einer Firmware ───────────────────────────────────────────────────
struct FieldsList: View {
    let fields: [FieldDef]
    @Binding var value: JSONValue
    let editable: Bool

    var body: some View {
        ForEach(fields) { f in
            FieldRow(field: f, value: $value.field(f.key), parent: value, editable: editable)
        }
    }
}

private struct FieldRow: View {
    let field: FieldDef
    @Binding var value: JSONValue
    let parent: JSONValue
    let editable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
            if let help = field.help, !help.isEmpty, field.type != "locations", field.type != "stops" {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var control: some View {
        switch field.type {
        case "select":
            Picker(field.label, selection: $value.string) {
                ForEach(field.options ?? [], id: \.self) { o in
                    Text(o.count > 1 ? o[1] : (o.first ?? "")).tag(o.first ?? "")
                }
            }
            .disabled(!editable)

        case "number":
            LabeledContent {
                TextField("0", value: $value.int, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 90)
                    .disabled(!editable)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                    if let lo = field.min, let hi = field.max {
                        Text("\(Int(lo))–\(Int(hi))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case "checkbox":
            Toggle(field.label, isOn: $value.bool)
                .disabled(!editable)

        case "team":
            NavigationLink {
                TeamPicker(selection: $value.string, league: parent["league"]?.stringValue ?? "bl1", editable: editable)
            } label: {
                LabeledContent(field.label, value: value.stringValue ?? "–")
            }

        case "text":
            TextField(field.label, text: $value.string)
                .disabled(!editable)

        case "locations":
            NavigationLink {
                LocationsEditor(items: $value.array, editable: editable, help: field.help)
            } label: {
                LabeledContent(field.label, value: countText(value.arrayValue?.count ?? 0, "Ort", "Orte"))
            }

        case "stops":
            NavigationLink {
                StopsEditor(items: $value.array, editable: editable, help: field.help)
            } label: {
                LabeledContent(field.label, value: countText(value.arrayValue?.count ?? 0, "Strecke", "Strecken"))
            }

        case "calendars":
            NavigationLink {
                CalendarsEditor(value: $value, editable: editable)
            } label: {
                LabeledContent(field.label, value: calendarSummary)
            }

        default:
            LabeledContent(field.label, value: "in der WebApp")
        }
    }

    private func countText(_ n: Int, _ one: String, _ many: String) -> String {
        n == 0 ? "keine" : "\(n) \(n == 1 ? one : many)"
    }

    private var calendarSummary: String {
        let n = (value["selected"]?.arrayValue?.count ?? 0) + (value["ics"]?.arrayValue?.count ?? 0)
        return n == 0 ? "keine" : "\(n) ausgewählt"
    }
}

// ── Suche (Orte, Haltestellen) ──────────────────────────────────────────────
struct SearchList: View {
    let prompt: String
    let search: (String) async throws -> [JSONValue]
    let titleOf: (JSONValue) -> String
    let subtitleOf: (JSONValue) -> String?
    var extra: (String, () -> Void)? = nil
    let onPick: (JSONValue) -> Void

    @State private var query = ""
    @State private var results: [JSONValue] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        IPList {
            if let extra {
                Section {
                    Button(extra.0, action: extra.1)
                }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            Section {
                ForEach(results.indices, id: \.self) { i in
                    Button {
                        onPick(results[i])
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titleOf(results[i])).foregroundStyle(.primary)
                            if let sub = subtitleOf(results[i]), !sub.isEmpty {
                                Text(sub).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if loading {
                ProgressView()
            } else if results.isEmpty && query.count >= 2 && error == nil {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { results = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            loading = true
            error = nil
            do {
                let r = try await search(q)
                if !Task.isCancelled { results = r }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

// ── Orte (Wetter) ───────────────────────────────────────────────────────────
struct LocationsEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var items: [JSONValue]
    let editable: Bool
    var help: String?
    @State private var adding = false

    var body: some View {
        IPList {
            Section {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items[i]["n"]?.stringValue ?? "Ort")
                        if let l = items[i]["label"]?.stringValue, !l.isEmpty {
                            Text(l).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { items.remove(atOffsets: $0) }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                .deleteDisabled(!editable)
                .moveDisabled(!editable)
            } footer: {
                if let help { Text(help) }
            }
            if editable {
                Section {
                    Button { adding = true } label: { Label("Ort hinzufügen", systemImage: "plus") }
                }
            }
        }
        .navigationTitle("Orte")
        .toolbar { if editable && !items.isEmpty { EditButton() } }
        .sheet(isPresented: $adding) {
            NavigationStack {
                SearchList(prompt: "Stadt oder Postleitzahl",
                           search: { q in try await model.withServer { try await $0.geocode(q) } },
                           titleOf: { $0["n"]?.stringValue ?? "Ort" },
                           subtitleOf: { $0["label"]?.stringValue }) { picked in
                    items.append(picked)
                    adding = false
                }
                .navigationTitle("Ort suchen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { adding = false } }
                }
            }
        }
    }
}

// ── Haltestellen / Strecken (Abfahrten) ─────────────────────────────────────
struct StopsEditor: View {
    @Binding var items: [JSONValue]
    let editable: Bool
    var help: String?
    @State private var adding = false

    var body: some View {
        IPList {
            Section {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items[i]["name"]?.stringValue ?? "Haltestelle")
                        if let to = items[i]["to"]?["name"]?.stringValue {
                            Label(to, systemImage: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("alle Abfahrten").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { items.remove(atOffsets: $0) }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                .deleteDisabled(!editable)
                .moveDisabled(!editable)
            } footer: {
                if let help { Text(help) }
            }
            if editable && items.count < 8 {
                Section {
                    Button { adding = true } label: { Label("Strecke hinzufügen", systemImage: "plus") }
                }
            }
        }
        .navigationTitle("Haltestellen")
        .toolbar { if editable && !items.isEmpty { EditButton() } }
        .sheet(isPresented: $adding) {
            StopRouteSheet { stop in
                items.append(stop)
                adding = false
            } onCancel: {
                adding = false
            }
        }
    }
}

private struct StopRouteSheet: View {
    @Environment(AppModel.self) private var model
    let onDone: (JSONValue) -> Void
    let onCancel: () -> Void
    @State private var start: JSONValue?

    private static func clean(_ v: JSONValue) -> JSONValue {
        .object(["id": v["id"] ?? .string(""), "name": v["name"] ?? .string("Haltestelle"), "src": v["src"] ?? .string("transitous")])
    }

    private func search(_ q: String) async throws -> [JSONValue] {
        try await model.withServer { try await $0.stops(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let start {
                    SearchList(prompt: "Zielhaltestelle",
                               search: search,
                               titleOf: { $0["name"]?.stringValue ?? "Haltestelle" },
                               subtitleOf: { _ in nil },
                               extra: ("Ohne Ziel – alle Abfahrten zeigen", { onDone(Self.clean(start)) })) { to in
                        var s = Self.clean(start)
                        s["to"] = Self.clean(to)
                        onDone(s)
                    }
                    .id("ziel")
                    .navigationTitle("Ziel (optional)")
                } else {
                    SearchList(prompt: "Starthaltestelle",
                               search: search,
                               titleOf: { $0["name"]?.stringValue ?? "Haltestelle" },
                               subtitleOf: { _ in nil }) { picked in
                        start = picked
                    }
                    .id("start")
                    .navigationTitle("Start")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: onCancel) }
            }
        }
    }
}

// ── Lieblingsteam (Bundesliga) ──────────────────────────────────────────────
struct TeamPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    let league: String
    let editable: Bool

    @State private var teams: [String] = []
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?

    private var filtered: [String] {
        query.isEmpty ? teams : teams.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        IPList {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.footnote)
                }
            }
            Section {
                ForEach(filtered, id: \.self) { name in
                    Button {
                        selection = name
                        dismiss()
                    } label: {
                        HStack {
                            Text(name).foregroundStyle(.primary)
                            Spacer()
                            if name == selection {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .disabled(!editable)
                }
            }
        }
        .overlay { if loading { ProgressView() } }
        .searchable(text: $query, prompt: "Team suchen")
        .navigationTitle("Lieblingsteam")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                teams = try await model.withServer { try await $0.teams(league: league) }
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

// ── Kalender ────────────────────────────────────────────────────────────────
struct CalendarsEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var value: JSONValue
    let editable: Bool

    @State private var available: [JSONValue] = []
    @State private var loading = false
    @State private var error: String?
    @State private var addingICS = false
    @State private var icsName = ""
    @State private var icsURL = ""

    private enum Mode: String { case account, custom, none }

    private var mode: Mode {
        if value["icloud"]?["account"]?.boolValue == true { return .account }
        if let id = value["icloud"]?["appleId"]?.stringValue, !id.isEmpty { return .custom }
        return .none
    }

    private var modeBinding: Binding<Mode> {
        Binding(get: { mode }, set: { m in
            switch m {
            case .account: value["icloud"] = .object(["account": .bool(true)])
            case .none:
                value["icloud"] = .null
                value["selected"] = .array([])
            case .custom: break
            }
            available = []
        })
    }

    private var selected: [JSONValue] { value["selected"]?.arrayValue ?? [] }

    private func isSelected(_ url: String) -> Bool { selected.contains { $0["url"]?.stringValue == url } }

    private func toggle(_ cal: JSONValue) {
        guard let url = cal["url"]?.stringValue else { return }
        var list = selected
        if isSelected(url) { list.removeAll { $0["url"]?.stringValue == url } }
        else {
            list.append(.object(["url": .string(url),
                                 "name": cal["name"] ?? .string("Kalender"),
                                 "color": cal["color"] ?? .string("0A84FF")]))
        }
        value["selected"] = .array(list)
    }

    private static func color(_ hex: String?) -> Color {
        let h = (hex ?? "0A84FF").replacingOccurrences(of: "#", with: "")
        return Color(hex: UInt32(h, radix: 16) ?? 0x0A84FF)
    }

    var body: some View {
        IPList {
            Section {
                Picker("Apple-Kalender", selection: modeBinding) {
                    Text("Mein Apple-Konto").tag(Mode.account)
                    if mode == .custom { Text("Eigene Apple-ID").tag(Mode.custom) }
                    Text("Keiner").tag(Mode.none)
                }
                .disabled(!editable)
                if mode == .account {
                    if let acc = model.data?.icloudAccount {
                        LabeledContent("Konto", value: acc)
                        if editable {
                            Button {
                                load()
                            } label: {
                                HStack {
                                    Text(available.isEmpty ? "Kalender laden" : "Neu laden")
                                    Spacer()
                                    if loading { ProgressView() }
                                }
                            }
                            .disabled(loading)
                        }
                    } else {
                        Label("Noch kein Apple-Konto hinterlegt – in der WebApp unter Einstellungen → Apple-Konto eintragen.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } else if mode == .custom {
                    Text("Diese Vorlage nutzt eine eigene Apple-ID. Ändern geht in der WebApp.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.footnote)
                }
            } header: {
                Text("iCloud")
            }

            if mode != .none {
                Section("Angezeigte Kalender") {
                    let list = available.isEmpty ? selected : available
                    if list.isEmpty {
                        Text(mode == .account ? "„Kalender laden“ tippen" : "keine")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(list.indices, id: \.self) { i in
                        let cal = list[i]
                        Button {
                            toggle(cal)
                        } label: {
                            HStack {
                                Circle().fill(Self.color(cal["color"]?.stringValue)).frame(width: 10, height: 10)
                                Text(cal["name"]?.stringValue ?? "Kalender").foregroundStyle(.primary)
                                Spacer()
                                if isSelected(cal["url"]?.stringValue ?? "") {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .disabled(!editable || available.isEmpty)
                    }
                }
            }

            Section {
                let ics = value["ics"]?.arrayValue ?? []
                ForEach(ics.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ics[i]["name"]?.stringValue ?? "Kalender")
                        Text(ics[i]["url"]?.stringValue ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .onDelete { idx in
                    var list = value["ics"]?.arrayValue ?? []
                    list.remove(atOffsets: idx)
                    value["ics"] = .array(list)
                }
                .deleteDisabled(!editable)
                if editable {
                    Button { addingICS = true } label: { Label("ICS-Kalender hinzufügen", systemImage: "plus") }
                }
            } header: {
                Text("Abonnierte Kalender (ICS)")
            } footer: {
                Text("Öffentliche Kalender-Links, z. B. Feiertage, Müllabfuhr oder geteilte Google-Kalender.")
            }
        }
        .navigationTitle("Kalender")
        .navigationBarTitleDisplayMode(.inline)
        .alert("ICS-Kalender", isPresented: $addingICS) {
            TextField("Name", text: $icsName)
            TextField("https://…", text: $icsURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("Abbrechen", role: .cancel) { icsName = ""; icsURL = "" }
            Button("Hinzufügen") {
                let url = icsURL.trimmingCharacters(in: .whitespaces)
                guard !url.isEmpty else { return }
                var list = value["ics"]?.arrayValue ?? []
                list.append(.object(["url": .string(url),
                                     "name": .string(icsName.isEmpty ? "Kalender" : icsName),
                                     "color": .string("0A84FF")]))
                value["ics"] = .array(list)
                icsName = ""
                icsURL = ""
            }
        } message: {
            Text("Adresse des Kalender-Abos (webcal:// oder https://)")
        }
    }

    private func load() {
        loading = true
        error = nil
        Task {
            do {
                available = try await model.withServer { try await $0.icloudCalendars() }
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
