import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmLogout = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("Adresse") {
                        Text(model.serverURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Konto", value: model.username)
                    LabeledContent("Status") {
                        switch model.serverReachable {
                        case .some(true):
                            Label("Verbunden", systemImage: "checkmark.icloud").foregroundStyle(.green)
                        case .some(false):
                            Label("Offline", systemImage: "icloud.slash").foregroundStyle(.orange)
                        case .none:
                            Text("–").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Letzter Abgleich") {
                        if let d = model.lastSync {
                            Text(d.formatted(.relative(presentation: .named)))
                        } else {
                            Text("noch nie").foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await model.syncNow() }
                    } label: {
                        HStack {
                            Text("Jetzt abgleichen")
                            Spacer()
                            if model.syncing { ProgressView() }
                        }
                    }
                    .disabled(model.syncing)
                }

                if let e = model.syncError {
                    Section {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if !model.pending.isEmpty {
                    Section {
                        ForEach(model.pending) { p in
                            LabeledContent(model.device(p.deviceId)?.name ?? "Gerät",
                                           value: [model.template(p.templateId)?.name, p.ui != nil ? "Darstellung" : nil]
                                               .compactMap { $0 }.joined(separator: " + "))
                        }
                    } header: {
                        Text("Wartet auf den Server")
                    } footer: {
                        Text("Offline übertragene Vorlagen und Darstellungen meldet die App automatisch, sobald der Server erreichbar ist.")
                    }
                }

                Section {
                    Toggle("Selbst signiertes Zertifikat erlauben", isOn: $model.allowSelfSigned)
                } footer: {
                    Text("Für die HTTPS-Adresse des Containers (Port 8791). Gilt nur für die eingetragene Server-Adresse.")
                }

                Section("Offline gespeichert") {
                    LabeledContent("Firmwares", value: "\(model.cached.count)")
                    LabeledContent("Geräte", value: "\(model.data?.devices.count ?? 0)")
                    LabeledContent("Vorlagen", value: "\(model.data?.templates.count ?? 0)")
                }

                Section {
                    Button("Abmelden", role: .destructive) { confirmLogout = true }
                } footer: {
                    Text("Entfernt Zugangsdaten, gespeicherte Firmwares und Gerätedaten aus der App.")
                }

                Section {
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Einstellungen")
            .confirmationDialog("Abmelden?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) { model.logout() }
            } message: {
                Text("Ohne Anmeldung kann die App keine Displays mehr einrichten.")
            }
        }
    }
}
