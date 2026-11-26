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
            IPList {
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
                        Text("Meine Geräte")
                    } footer: {
                        Text("Geräte und WLAN-Zugänge legst du in der WebApp an. Vorlagen, Design und Helligkeit überträgt die App direkt im WLAN – auch ohne Server.")
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
                        Text("Weitere Geräte im WLAN")
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
            .navigationTitle("Geräte")
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
                    .font(.dm(.subheadline, 14, .bold))
                Text(detail)
                    .font(.dm(.footnote, 13))
                    .foregroundStyle(Theme.fg2)
            }
        } icon: {
            Image(systemName: "icloud.slash")
                .foregroundStyle(Theme.warn)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var s = "Geräte lassen sich trotzdem einrichten"
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
            Tile(systemImage: "display", size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.dm(.body, 16, .bold))
                Text(device.templateName ?? model.firmwareName(device.firmware))
                    .font(.dm(.subheadline, 14))
                    .foregroundStyle(Theme.fg2)
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
        HStack(spacing: 6) {
            if pending {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.warn)
                    .accessibilityLabel("Wartet auf den Server")
            }
            Badge(text: visible ? "Im WLAN" : "Nicht gefunden", color: visible ? Theme.ok : Theme.fg2)
        }
        .accessibilityElement(children: .combine)
    }
}
