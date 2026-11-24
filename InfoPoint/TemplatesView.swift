import SwiftUI

// Symbol und Farbe je Firmware
enum FirmwareStyle {
    static func symbol(_ id: String) -> String {
        switch id {
        case "bundesliga": return "soccerball"
        case "wetter": return "cloud.sun"
        case "kalender": return "calendar"
        case "abfahrten": return "tram"
        case "multi": return "square.stack.3d.up"
        default: return "cpu"
        }
    }

    static func color(_ id: String) -> Color { Schedule.colors[id] ?? .accentColor }
}

struct FirmwareIcon: View {
    let id: String
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: FirmwareStyle.symbol(id))
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(FirmwareStyle.color(id))
            .frame(width: size, height: size)
            .background(FirmwareStyle.color(id).opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct TemplatesView: View {
    @Environment(AppModel.self) private var model
    @State private var showNew = false
    @State private var path: [String] = []
    @State private var toDelete: TemplateInfo?
    @State private var error: String?

    private struct TemplateGroup: Identifiable {
        let id: String
        let name: String
        let items: [TemplateInfo]
    }

    // nach Firmware gruppiert, Reihenfolge wie im Katalog
    private var groups: [TemplateGroup] {
        let all = model.templates
        var order = model.catalog.map(\.id)
        for t in all where !order.contains(t.firmware) { order.append(t.firmware) }
        return order.compactMap { fid in
            let items = all.filter { $0.firmware == fid }
            return items.isEmpty ? nil : TemplateGroup(id: fid, name: model.firmwareName(fid), items: items)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            IPList {
                if !model.online {
                    Section {
                        Label("Vorlagen anlegen und bearbeiten geht nur, wenn der Server erreichbar ist. Übertragen auf Geräte klappt auch offline.",
                              systemImage: "icloud.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(groups) { g in
                    Section(g.name) {
                        ForEach(g.items) { t in
                            NavigationLink(value: t.id) {
                                TemplateRow(template: t)
                            }
                            .swipeActions {
                                if t.canEdit == true && model.online {
                                    Button(role: .destructive) {
                                        toDelete = t
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView("Keine Vorlagen",
                                           systemImage: "square.grid.2x2",
                                           description: Text("Lege mit + eine Vorlage an."))
                }
            }
            .navigationTitle("Vorlagen")
            .navigationDestination(for: String.self) { id in
                TemplateEditorView(templateId: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neue Vorlage")
                    .disabled(!model.online || model.catalog.isEmpty)
                }
            }
            .refreshable { await model.syncNow() }
            .sheet(isPresented: $showNew) {
                NewTemplateSheet { id in path.append(id) }
            }
            .confirmationDialog("Vorlage löschen?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible, presenting: toDelete) { t in
                Button("„\(t.name)“ löschen", role: .destructive) {
                    Task {
                        do { try await model.deleteTemplate(id: t.id) } catch { self.error = error.localizedDescription }
                    }
                }
            } message: { _ in
                Text("Geräte mit dieser Vorlage behalten ihre Einstellungen.")
            }
            .alert("Fehler", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }
}

private struct TemplateRow: View {
    @Environment(AppModel.self) private var model
    let template: TemplateInfo

    private var subtitle: String {
        var parts: [String] = []
        if !template.members.isEmpty { parts.append(template.members.map(model.firmwareName).joined(separator: ", ")) }
        if template.shared { parts.append("für alle") }
        else if !template.mine, let o = template.ownerName { parts.append("von \(o)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            FirmwareIcon(id: template.firmware)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.body.weight(.semibold))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if template.canEdit != true {
                Image(systemName: "lock")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Nur lesen")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// ── Neue Vorlage ────────────────────────────────────────────────────────────
struct NewTemplateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreated: (String) -> Void

    @State private var name = ""
    @State private var firmware = ""
    @State private var members: Set<String> = []
    @State private var busy = false
    @State private var error: String?

    private var entry: CatalogEntry? { model.catalogEntry(firmware) }
    private var singles: [CatalogEntry] { model.catalog.filter { !$0.multi } }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !firmware.isEmpty
            && (entry?.multi != true || members.count >= 2)
    }

    var body: some View {
        NavigationStack {
            IPForm {
                Section("Name") {
                    TextField("z. B. Küche morgens", text: $name)
                }
                Section {
                    Picker("Firmware", selection: $firmware) {
                        ForEach(model.catalog) { c in
                            Label(c.name, systemImage: FirmwareStyle.symbol(c.id)).tag(c.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Firmware")
                } footer: {
                    if let d = entry?.description, !d.isEmpty { Text(d) }
                }
                if entry?.multi == true {
                    Section {
                        ForEach(singles) { c in
                            Toggle(isOn: Binding(get: { members.contains(c.id) },
                                                 set: { on in if on { members.insert(c.id) } else { members.remove(c.id) } })) {
                                Label(c.name, systemImage: FirmwareStyle.symbol(c.id))
                            }
                        }
                    } header: {
                        Text("Anzeigen")
                    } footer: {
                        Text("Mindestens zwei auswählen. Wann was läuft, legst du danach im Zeitplan fest.")
                    }
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Neue Vorlage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Anlegen", action: create).disabled(!valid)
                    }
                }
            }
            .onAppear {
                if firmware.isEmpty { firmware = model.catalog.first?.id ?? "" }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private func create() {
        busy = true
        error = nil
        let ordered = singles.map(\.id).filter { members.contains($0) }
        Task {
            do {
                let id = try await model.createTemplate(name: name.trimmingCharacters(in: .whitespaces),
                                                        firmware: firmware,
                                                        members: entry?.multi == true ? ordered : [])
                dismiss()
                onCreated(id)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
