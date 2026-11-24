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

    var body: some View {
        if let d = model.device(deviceId) {
            content(d)
        } else {
            ContentUnavailableView("Gerät nicht gefunden", systemImage: "display.trianglebadge.exclamationmark")
        }
    }

    private func content(_ d: DeviceInfo) -> some View {
        Form {
            statusSection(d)
            templateSection(d)

            Section {
                Button {
                    start(d, force: false)
                } label: {
                    Label("Auf Display übertragen", systemImage: "square.and.arrow.down.on.square")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .disabled(selected == nil || job?.running == true)
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
            if selected == nil { selected = d.templateId }
            ipText = model.manualIPs[d.id] ?? ""
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
            List {
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
