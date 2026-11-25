import SwiftUI
import UIKit

struct DeviceDetailView: View {
    @Environment(AppModel.self) private var model
    let deviceId: String

    @State private var selected: String?
    @State private var info: DisplayInfo?
    @State private var reachedURL: URL?
    @State private var checking = false
    @State private var checked = false
    @State private var ipText = ""
    @State private var job: TransferJob?
    @State private var ui = UiSettings()
    @State private var uiBusy = false
    @State private var uiMessage: String?
    @State private var uiError: String?
    @State private var loadedFor: String?   // Zustand nur beim ersten Öffnen laden – nicht nach Rückkehr aus der Design-Auswahl

    var body: some View {
        if let d = model.device(deviceId) {
            content(d)
        } else {
            ContentUnavailableView("Gerät nicht gefunden", systemImage: "display.trianglebadge.exclamationmark")
        }
    }

    private func content(_ d: DeviceInfo) -> some View {
        IPForm {
            statusSection(d)
            appearanceSection(d)
            templateSection(d)

            Section {
                Button {
                    start(d, force: false)
                } label: {
                    Label("Auf Display übertragen", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(selected == nil || job?.running == true)
                .primaryRow()
            }

            Section {
                Button {
                    start(d, force: true)
                } label: {
                    Label("Firmware neu aufspielen", systemImage: "arrow.clockwise")
                }
                .disabled(selected == nil || job?.running == true)
            } footer: {
                Text("Spielt die in der App gespeicherte Firmware erneut auf und sendet danach die gewählte Vorlage.")
            }

            Section {
                TextField("z. B. 192.168.30.60", text: $ipText)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .monospacedDigit()
                    .submitLabel(.done)
                    .onSubmit { saveIP(d) }
            } header: {
                Text("IP-Adresse (optional)")
            } footer: {
                Text("Nur nötig, wenn das Display nicht automatisch gefunden wird.")
            }
        }
        .navigationTitle(d.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deviceId) {
            if loadedFor != deviceId {
                loadedFor = deviceId
                selected = d.templateId
                ui = d.ui ?? UiSettings()
                ipText = model.manualIPs[d.id] ?? ""
            }
            await check(d)
        }
        .refreshable { await check(d) }
        .onChange(of: model.discovery.isVisible(tid: d.tokenId)) { _, visible in
            if visible && reachedURL == nil { Task { await check(d) } }
        }
        .sheet(item: $job, onDismiss: { Task { await check(d) } }) { j in
            TransferSheet(job: j)
        }
    }

    // ── Status ──────────────────────────────────────────────────────────────
    private func statusSection(_ d: DeviceInfo) -> some View {
        Section("Status") {
            LabeledContent("Verbindung") {
                if checking && !checked {
                    ProgressView()
                } else if let u = reachedURL {
                    Label(u.host ?? "", systemImage: "wifi")
                        .monospacedDigit()
                        .foregroundStyle(.green)
                } else {
                    Text("Nicht gefunden").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Firmware") {
                if let info {
                    Text("\(info.name) \(info.ver)")
                } else {
                    Text(model.firmwareName(d.firmware))
                }
            }
            LabeledContent("Vorlage", value: d.templateName ?? "–")
            if model.pendingCount(for: d.id) > 0 {
                Label("Änderung wird dem Server gemeldet, sobald er erreichbar ist", systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // ── Darstellung ─────────────────────────────────────────────────────────
    private func appearanceSection(_ d: DeviceInfo) -> some View {
        let dirty = ui != (d.ui ?? UiSettings())
        return Section {
            NavigationLink {
                PalettePicker(selection: $ui.palette)
            } label: {
                LabeledContent("Design") {
                    HStack(spacing: 8) {
                        PaletteChip(palette: Palettes.all[min(max(ui.palette, 0), Palettes.all.count - 1)], size: 22)
                        Text(Palettes.name(ui.palette))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Helligkeit") {
                    Text("\(ui.bright) %").monospacedDigit()
                }
                Slider(value: intSlider(\.bright), in: 5...100, step: 5) {
                    Text("Helligkeit")
                } minimumValueLabel: {
                    Image(systemName: "sun.min")
                } maximumValueLabel: {
                    Image(systemName: "sun.max")
                }
            }
            Picker("Bei Inaktivität", selection: $ui.smode) {
                Text("Bildschirmschoner").tag(0)
                Text("Nur dimmen").tag(1)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            Picker("Nach", selection: $ui.saver) {
                ForEach(SaverOptions.all, id: \.0) { opt in
                    Text(opt.1).tag(opt.0)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(ui.smode == 1 ? "Gedimmt auf" : "Helligkeit im Schoner") {
                    Text("\(ui.dim) %").monospacedDigit()
                }
                Slider(value: intSlider(\.dim), in: 0...100, step: 5) {
                    Text("Helligkeit im Ruhezustand")
                } minimumValueLabel: {
                    Image(systemName: "moon")
                } maximumValueLabel: {
                    Image(systemName: "sun.max")
                }
            }
            if ui.smode == 0 {
                Picker("Schrift der Uhr", selection: $ui.sfont) {
                    ForEach(ClockStyle.fonts, id: \.0) { f in
                        Text(f.1).tag(f.0)
                    }
                }
                Picker("Größe der Uhr", selection: $ui.ssize) {
                    ForEach(ClockStyle.sizes, id: \.0) { s in
                        Text(s.1).tag(s.0)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Schrift des Datums", selection: $ui.dfont) {
                    ForEach(ClockStyle.dateFonts, id: \.0) { f in
                        Text(f.1).tag(f.0)
                    }
                }
                .disabled(ui.dsize == 3)
                Picker("Größe des Datums", selection: $ui.dsize) {
                    ForEach(ClockStyle.dateSizes, id: \.0) { s in
                        Text(s.1).tag(s.0)
                    }
                }
                .pickerStyle(.segmented)
                SaverPreview(ui: ui)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            if dirty || uiBusy {
                Button {
                    applyUi(d)
                } label: {
                    HStack(spacing: 8) {
                        if uiBusy { ProgressView().tint(Theme.onAccent) }
                        Text("Darstellung übernehmen")
                    }
                }
                .disabled(uiBusy)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.vertical, 4)
            }
            if let uiError {
                Label(uiError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let uiMessage {
                Label(uiMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Darstellung")
        } footer: {
            Text("Wird direkt ans Display gesendet, wenn es im WLAN ist (es startet kurz neu) – sonst über den Server.")
        }
    }

    private func intSlider(_ key: WritableKeyPath<UiSettings, Int>) -> Binding<Double> {
        Binding(get: { Double(ui[keyPath: key]) }, set: { ui[keyPath: key] = Int($0.rounded()) })
    }

    private func applyUi(_ d: DeviceInfo) {
        uiBusy = true
        uiError = nil
        uiMessage = nil
        let wanted = ui
        Task {
            do {
                switch try await model.applyUi(wanted, to: d) {
                case .display: uiMessage = "Ans Display gesendet."
                case .server: uiMessage = "Gespeichert – das Display übernimmt es beim nächsten Abruf (≤ 20 s)."
                }
            } catch {
                uiError = error.localizedDescription
            }
            uiBusy = false
        }
    }

    // ── Vorlage ─────────────────────────────────────────────────────────────
    private func templateSection(_ d: DeviceInfo) -> some View {
        Section {
            Picker("Vorlage", selection: $selected) {
                Text("Bitte wählen").tag(String?.none)
                ForEach(model.templates) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name)
                        Text(subtitle(t))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(t.id))
                }
            }
            .pickerStyle(.navigationLink)

            if let t = model.template(selected) {
                ForEach(notes(d, t), id: \.text) { n in
                    Label(n.text, systemImage: n.icon)
                        .font(.footnote)
                        .foregroundStyle(n.warn ? Color.orange : Color.secondary)
                }
            }
        } header: {
            Text("Vorlage laden")
        }
    }

    private func subtitle(_ t: TemplateInfo) -> String {
        var s = model.firmwareName(t.firmware)
        if !t.members.isEmpty { s += " · " + t.members.map(model.firmwareName).joined(separator: ", ") }
        if !t.mine, let o = t.ownerName { s += " · von \(o)" }
        return s
    }

    private struct Note { let text: String; let icon: String; let warn: Bool }

    private func notes(_ d: DeviceInfo, _ t: TemplateInfo) -> [Note] {
        var out: [Note] = []
        let fw = model.cached[t.firmware]
        if fw == nil {
            out.append(Note(text: "Firmware „\(model.firmwareName(t.firmware))“ fehlt in der App – einmal mit dem Server abgleichen.",
                            icon: "exclamationmark.triangle.fill", warn: true))
        }
        if d.configs[t.id] == nil {
            out.append(Note(text: "Keine Konfiguration für dieses Gerät – im Server ein WLAN zuordnen und abgleichen.",
                            icon: "exclamationmark.triangle.fill", warn: true))
        }
        if let fw, let info {
            if info.fw != fw.id {
                out.append(Note(text: "Firmware wird gewechselt: \(info.name) → \(fw.name) \(fw.version)", icon: "arrow.left.arrow.right", warn: false))
            } else if info.build != fw.hash {
                out.append(Note(text: "Firmware-Update auf \(fw.version) (neuer Stand)", icon: "arrow.up.circle", warn: false))
            } else {
                out.append(Note(text: "Firmware ist aktuell – nur die Einstellungen werden gesendet.", icon: "checkmark.circle", warn: false))
            }
        }
        return out
    }

    // ── Aktionen ────────────────────────────────────────────────────────────
    private func check(_ d: DeviceInfo) async {
        checking = true
        if let r = await model.reach(d) {
            reachedURL = r.0
            info = r.1
        } else {
            reachedURL = nil
            info = nil
        }
        checking = false
        checked = true
    }

    private func saveIP(_ d: DeviceInfo) {
        let ip = ipText.trimmingCharacters(in: .whitespaces)
        if ip.isEmpty { model.manualIPs.removeValue(forKey: d.id) } else { model.manualIPs[d.id] = ip }
        Task { await check(d) }
    }

    private func start(_ d: DeviceInfo, force: Bool) {
        guard let t = model.template(selected) else { return }
        saveIP(d)
        let j = TransferJob(deviceName: d.name, templateName: t.name)
        job = j
        Task { await j.run(model: model, device: d, template: t, forceFirmware: force) }
    }
}

// ── Fortschritt ─────────────────────────────────────────────────────────────
struct TransferSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let job: TransferJob

    private var steps: [TransferJob.Step] {
        job.firmwareNeeded ? TransferJob.Step.allCases : [.connect, .config, .done]
    }

    var body: some View {
        NavigationStack {
            IPList {
                Section {
                    ForEach(steps, id: \.self) { s in
                        StepRow(step: s, job: job)
                    }
                } header: {
                    Text("\(job.templateName) → \(job.deviceName)")
                }

                if let e = job.error {
                    Section {
                        Label(e, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }

                if job.finished {
                    Section {
                        Label("Das Display startet mit der neuen Vorlage neu.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } footer: {
                        if model.serverReachable != true {
                            Text("Der Server erfährt davon, sobald er wieder erreichbar ist.")
                        }
                    }
                }
            }
            .navigationTitle("Übertragung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .disabled(job.running)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(job.running)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

private struct StepRow: View {
    let step: TransferJob.Step
    let job: TransferJob

    private enum Phase { case waiting, active, done, failed }

    private var state: Phase {
        if job.finished || job.step.rawValue > step.rawValue { return .done }
        if job.step == step { return job.error != nil ? .failed : .active }
        return .waiting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                icon.frame(width: 24, height: 24)
                Text(step.title)
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
                Spacer()
                if step == .firmware && state == .active {
                    Text(job.uploadProgress, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if step == .firmware && state == .active {
                ProgressView(value: job.uploadProgress)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .waiting:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .active:
            ProgressView()
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

// ── Design-Auswahl ──────────────────────────────────────────────────────────
struct PaletteChip: View {
    let palette: Palette
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(palette.bg)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .fill(palette.card)
                    .padding(size * 0.16)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(palette.accent)
                            .frame(width: size * 0.36, height: max(2, size * 0.1))
                            .padding(.leading, size * 0.26)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PalettePicker: View {
    @Binding var selection: Int
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Palettes.groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.0)
                            .font(.headline)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.1, id: \.self) { i in
                                let p = Palettes.all[i]
                                Button {
                                    selection = i
                                    dismiss()
                                } label: {
                                    VStack(spacing: 6) {
                                        PaletteChip(palette: p, size: 64)
                                            .overlay(alignment: .topTrailing) {
                                                if selection == i {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .symbolRenderingMode(.palette)
                                                        .foregroundStyle(.white, Color.accentColor)
                                                        .font(.title3)
                                                        .offset(x: 6, y: -6)
                                                }
                                            }
                                        Text(p.shortName)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 92)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(p.name)
                                .accessibilityAddTraits(selection == i ? .isSelected : [])
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("Design")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Vorschau des Bildschirmschoners im gewählten Design (Display 480 × 320)
struct SaverPreview: View {
    let ui: UiSettings

    var body: some View {
        let p = Palettes.all[min(max(ui.palette, 0), Palettes.all.count - 1)]
        GeometryReader { geo in
            let scale = geo.size.width / 480
            let px = ClockStyle.pixels[min(max(ui.ssize, 0), 2)] * scale
            VStack(spacing: 6 * scale) {
                Text("12:34")
                    .font(ClockStyle.font(ui.sfont, size: px))
                    .foregroundStyle(p.light ? Color.black : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if ui.dsize != 3 {
                    Text("Dienstag, 24. November")
                        .font(.system(size: ClockStyle.datePixels[min(max(ui.dsize, 0), 2)] * scale,
                                      weight: ui.dfont == 1 ? .semibold : .regular))
                        .foregroundStyle(p.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(p.bg)
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .accessibilityLabel("Vorschau des Bildschirmschoners")
    }
}
