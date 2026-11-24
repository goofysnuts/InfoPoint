import SwiftUI

struct DevicesView: View {
    @Environment(AppModel.self) private var model

    private var foreign: [Discovery.Found] {
        let known = Set(model.devices.map(\.tokenId))
        return model.discovery.found.values
            .filter { !known.contains($0.tid) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if model.serverReachable == false {
                    Section {
                        OfflineBanner()
                    }
                }

                if !model.devices.isEmpty {
                    Section {
                        ForEach(model.devices) { d in
                            NavigationLink(value: d.id) {
                                DeviceRow(device: d)
                            }
                        }
                    } header: {
                        Text("Meine Displays")
                    } footer: {
                        Text("Geräte, Vorlagen und WLAN-Zugänge legst du in der WebApp an. Die App überträgt sie direkt im WLAN.")
                    }
                }

                if !foreign.isEmpty {
                    Section {
                        ForEach(foreign) { f in
                            LabeledContent {
                                Text(f.url?.host ?? "…")
                                    .monospacedDigit()
                            } label: {
                                Label(f.name, systemImage: "display")
                            }
                        }
                    } header: {
                        Text("Weitere Displays im WLAN")
                    } footer: {
                        Text("Diese Displays gehören zu keinem Gerät deines Kontos.")
                    }
                }
            }
            .overlay {
                if model.devices.isEmpty {
                    if model.data == nil {
                        ContentUnavailableView {
                            Label("Noch kein Abgleich", systemImage: "arrow.triangle.2.circlepath")
                        } description: {
                            Text("Die App braucht einmal den Server, um Geräte, Vorlagen und Firmwares zu laden.")
                        } actions: {
                            Button("Jetzt abgleichen") { Task { await model.syncNow() } }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.syncing)
                        }
                    } else {
                        ContentUnavailableView("Keine Geräte",
                                               systemImage: "display",
                                               description: Text("Lege in der WebApp unter „Geräte“ ein Gerät an."))
                    }
                }
            }
            .navigationTitle("Displays")
            .navigationDestination(for: String.self) { id in
                DeviceDetailView(deviceId: id)
            }
            .refreshable {
                model.discovery.restart()
                await model.syncNow()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.syncing {
                        ProgressView()
                    }
                }
            }
        }
    }
}

struct OfflineBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Server offline")
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var s = "Displays lassen sich trotzdem einrichten"
        if let d = model.lastSync {
            s += " – Stand: \(d.formatted(date: .abbreviated, time: .shortened))"
        }
        if !model.pending.isEmpty {
            s += ". \(model.pending.count) Änderung(en) werden später gemeldet."
        }
        return s
    }
}

struct DeviceRow: View {
    @Environment(AppModel.self) private var model
    let device: DeviceInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "display")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.semibold))
                Text(device.templateName ?? model.firmwareName(device.firmware))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            StatusPill(visible: model.discovery.isVisible(tid: device.tokenId),
                       pending: model.pendingCount(for: device.id) > 0)
        }
        .padding(.vertical, 2)
    }
}

struct StatusPill: View {
    let visible: Bool
    var pending = false

    var body: some View {
        HStack(spacing: 5) {
            if pending {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Wartet auf den Server")
            }
            Circle()
                .fill(visible ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(visible ? "Im WLAN" : "Nicht gefunden")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
