import SwiftUI

struct FirmwaresView: View {
    @Environment(AppModel.self) private var model

    private var ids: [String] {
        var list = (model.data?.firmwares ?? []).map(\.id)
        for id in model.cached.keys.sorted() where !list.contains(id) { list.append(id) }
        return list
    }

    // wird aus den Einstellungen geöffnet (dort liegt der NavigationStack)
    var body: some View {
            IPList {
                Section {
                    ForEach(ids, id: \.self) { id in
                        FirmwareRow(id: id)
                    }
                } footer: {
                    Text("Neue Firmwares lädt die App automatisch, sobald der Server erreichbar ist – beim Öffnen und regelmäßig im Hintergrund. Gespeicherte Firmwares lassen sich jederzeit offline aufspielen.")
                }
            }
            .overlay {
                if ids.isEmpty {
                    ContentUnavailableView("Keine Firmwares",
                                           systemImage: "cpu",
                                           description: Text("Nach dem ersten Abgleich mit dem Server liegen hier alle Firmwares."))
                }
            }
            .navigationTitle("Firmwares")
            .refreshable { await model.syncNow() }
    }
}

private struct FirmwareRow: View {
    @Environment(AppModel.self) private var model
    let id: String

    private enum Status { case ok, loading, outdated, missing }

    private var server: FirmwareInfo? { model.data?.firmwares.first { $0.id == id } }
    private var local: FirmwareInfo? { model.cached[id] }

    private var status: Status {
        if model.downloading.contains(id) { return .loading }
        guard let local else { return .missing }
        if let server, server.hash != local.hash { return .outdated }
        return .ok
    }

    var body: some View {
        let f = local ?? server
        HStack(spacing: 12) {
            Image(systemName: (f?.multi ?? false) ? "square.stack.3d.up" : "cpu")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(f?.name ?? id)
                    .font(.dm(.body, 16, .bold))
                if let f {
                    Text("Version \(f.version) · \(ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file))")
                        .font(.dm(.subheadline, 14))
                        .foregroundStyle(Theme.fg2)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            statusView
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .ok:
            Label("Offline verfügbar", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.ok)
                .font(.title3)
        case .loading:
            ProgressView()
                .accessibilityLabel("Wird geladen")
        case .outdated:
            Label("Update ausstehend", systemImage: "arrow.down.circle")
                .font(.dm(.caption, 12))
                .foregroundStyle(Theme.warn)
        case .missing:
            Label("Fehlt", systemImage: "exclamationmark.circle")
                .font(.dm(.caption, 12))
                .foregroundStyle(Theme.danger)
        }
    }
}
