import SwiftUI
import UIKit

// Vorlage mit mehreren Firmwares: Anzeigen, Einstellungen je Anzeige, Zeitplan
struct MultiEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var app: JSONValue
    let editable: Bool

    private var members: [String] { (app["members"]?.arrayValue ?? []).compactMap(\.stringValue) }
    private var singles: [CatalogEntry] { model.catalog.filter { !$0.multi } }
    private var sched: Binding<JSONValue> { $app.field("sched") }
    private var rules: Binding<[JSONValue]> { sched.field("rules").array }

    var body: some View {
        Section {
            ForEach(singles) { c in
                Toggle(isOn: memberBinding(c)) {
                    Label(c.name, systemImage: FirmwareStyle.symbol(c.id))
                }
                .disabled(!editable || (members.contains(c.id) && members.count <= 2))
            }
        } header: {
            Text("Anzeigen")
        } footer: {
            Text("Mindestens zwei.")
        }

        Section("Einstellungen je Anzeige") {
            ForEach(members, id: \.self) { id in
                if let entry = model.catalogEntry(id) {
                    NavigationLink {
                        IPForm {
                            FieldsList(fields: entry.fields, value: $app.field("apps").field(id), editable: editable)
                        }
                        .navigationTitle(entry.name)
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack(spacing: 12) {
                            FirmwareIcon(id: id, size: 30)
                            Text(entry.name)
                        }
                    }
                }
            }
        }

        Section {
            Picker("Sonst anzeigen", selection: sched.field("def").string) {
                ForEach(members, id: \.self) { Text(model.firmwareName($0)).tag($0) }
            }
            .disabled(!editable)
            Picker("Wechsel bei Überschneidung", selection: rotBinding) {
                ForEach(Schedule.rotations, id: \.0) { Text($0.1).tag($0.0) }
            }
            .disabled(!editable)

            ForEach(rules.wrappedValue.indices, id: \.self) { i in
                NavigationLink {
                    RuleEditor(rule: ruleBinding(i), members: members, editable: editable)
                } label: {
                    RuleRow(rule: rules.wrappedValue[i])
                }
            }
            .onDelete { rules.wrappedValue.remove(atOffsets: $0) }
            .onMove { rules.wrappedValue.move(fromOffsets: $0, toOffset: $1) }
            .deleteDisabled(!editable)
            .moveDisabled(!editable)

            if editable {
                Button {
                    let def = sched.wrappedValue["def"]?.stringValue ?? ""
                    let a = members.first { $0 != def } ?? members.first ?? ""
                    rules.wrappedValue.append(.object(["a": .string(a), "d": .int(31), "f": .int(6 * 60), "t": .int(9 * 60)]))
                } label: {
                    Label("Regel hinzufügen", systemImage: "plus")
                }
            }
        } header: {
            Text("Zeitplan")
        } footer: {
            Text("Passen mehrere Regeln gleichzeitig (z. B. Wetter 07–10 Uhr und Abfahrten 08–09 Uhr), wechseln sich die Anzeigen im eingestellten Rhythmus ab. Jeder Wechsel startet das Display kurz neu (ca. 5 s). Passt keine Regel, läuft „Sonst anzeigen“.")
        }

        Section("Wochenübersicht") {
            WeekPreview(rules: rules.wrappedValue,
                        def: sched.wrappedValue["def"]?.stringValue ?? "",
                        members: members)
                .padding(.vertical, 6)
        }
    }

    private var rotBinding: Binding<Int> {
        Binding(get: { sched.wrappedValue["rot"]?.intValue ?? 120 },
                set: { newValue in
                    var s = sched.wrappedValue
                    s["rot"] = .int(newValue)
                    sched.wrappedValue = s
                })
    }

    private func ruleBinding(_ i: Int) -> Binding<JSONValue> {
        Binding(get: { rules.wrappedValue.indices.contains(i) ? rules.wrappedValue[i] : .object([:]) },
                set: { v in if rules.wrappedValue.indices.contains(i) { rules.wrappedValue[i] = v } })
    }

    private func memberBinding(_ c: CatalogEntry) -> Binding<Bool> {
        Binding(get: { members.contains(c.id) }, set: { on in
            var list = members
            var apps = app["apps"]?.objectValue ?? [:]
            if on {
                guard !list.contains(c.id) else { return }
                // Reihenfolge wie im Katalog
                list = singles.map(\.id).filter { list.contains($0) || $0 == c.id }
                if apps[c.id] == nil {
                    var defaults: [String: JSONValue] = [:]
                    for f in c.fields { defaults[f.key] = f.default ?? .null }
                    apps[c.id] = .object(defaults)
                }
            } else {
                guard list.count > 2 else { return }
                list.removeAll { $0 == c.id }
                apps[c.id] = nil
                var s = app["sched"] ?? .object([:])
                let kept = (s["rules"]?.arrayValue ?? []).filter { $0["a"]?.stringValue != c.id }
                s["rules"] = .array(kept)
                if s["def"]?.stringValue == c.id { s["def"] = .string(list.first ?? "") }
                app["sched"] = s
            }
            app["members"] = .array(list.map { .string($0) })
            app["apps"] = .object(apps)
        })
    }
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let rule: JSONValue

    var body: some View {
        let a = rule["a"]?.stringValue ?? ""
        let f = rule["f"]?.intValue ?? 0
        let t = rule["t"]?.intValue ?? 0
        HStack(spacing: 12) {
            FirmwareIcon(id: a, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.firmwareName(a))
                Text("\(Schedule.daysText(rule["d"]?.intValue ?? 127)) · \(f == t ? "ganzer Tag" : "\(Schedule.hm(f))–\(Schedule.hm(t))")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RuleEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var rule: JSONValue
    let members: [String]
    let editable: Bool

    private func timeBinding(_ key: String) -> Binding<Date> {
        Binding(get: {
            let m = rule[key]?.intValue ?? 0
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date(timeIntervalSince1970: 0)) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            rule[key] = .int((c.hour ?? 0) * 60 + (c.minute ?? 0))
        })
    }

    private var days: Int { rule["d"]?.intValue ?? 127 }

    private func setDays(_ v: Int) { if v != 0 { rule["d"] = .int(v) } }

    var body: some View {
        let f = rule["f"]?.intValue ?? 0
        let t = rule["t"]?.intValue ?? 0
        IPForm {
            Section {
                Picker("Anzeige", selection: $rule.field("a").string) {
                    ForEach(members, id: \.self) { id in
                        Label(model.firmwareName(id), systemImage: FirmwareStyle.symbol(id)).tag(id)
                    }
                }
            }
            Section {
                DatePicker("Von", selection: timeBinding("f"), displayedComponents: .hourAndMinute)
                DatePicker("Bis", selection: timeBinding("t"), displayedComponents: .hourAndMinute)
            } header: {
                Text("Uhrzeit")
            } footer: {
                Text(f == t ? "Gleiche Zeit = ganzer Tag." : t < f ? "Läuft über Mitternacht." : "")
            }
            Section("Wochentage") {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { b in
                        let on = days & (1 << b) != 0
                        Button {
                            setDays(days ^ (1 << b))
                        } label: {
                            Text(Schedule.days[b])
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(on ? Color.accentColor : Color(.tertiarySystemFill),
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Schedule.days[b])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                HStack {
                    Button("Mo–Fr") { setDays(31) }
                    Spacer()
                    Button("Wochenende") { setDays(96) }
                    Spacer()
                    Button("Täglich") { setDays(127) }
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
        }
        .disabled(!editable)
        .navigationTitle("Regel")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Wochenübersicht: je Tag ein Balken, Überschneidungen als übereinanderliegende Streifen
struct WeekPreview: View {
    @Environment(AppModel.self) private var model
    let rules: [JSONValue]
    let def: String
    let members: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<7, id: \.self) { wd in
                HStack(spacing: 8) {
                    Text(Schedule.days[wd])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .leading)
                    Canvas { ctx, size in
                        let step = 15
                        var m = 0
                        while m < 1440 {
                            let apps = Schedule.apps(rules: rules, def: def, members: members, weekday: wd, minute: m)
                            var end = m + step
                            while end < 1440 && Schedule.apps(rules: rules, def: def, members: members, weekday: wd, minute: end) == apps {
                                end += step
                            }
                            let x0 = size.width * CGFloat(m) / 1440
                            let x1 = size.width * CGFloat(end) / 1440
                            let h = size.height / CGFloat(max(apps.count, 1))
                            for (k, a) in apps.enumerated() {
                                ctx.fill(Path(CGRect(x: x0, y: h * CGFloat(k), width: x1 - x0, height: h)),
                                         with: .color(Schedule.colors[a] ?? .gray))
                            }
                            m = end
                        }
                    }
                    .frame(height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            HStack(spacing: 8) {
                Color.clear.frame(width: 22, height: 1)
                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                        Text("\(h)")
                        if h != 24 { Spacer() }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            }
            HStack(spacing: 14) {
                ForEach(members, id: \.self) { id in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Schedule.colors[id] ?? .gray).frame(width: 10, height: 10)
                        Text(model.firmwareName(id))
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wochenübersicht des Zeitplans")
    }
}
