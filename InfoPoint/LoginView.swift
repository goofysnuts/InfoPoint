import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var server = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @State private var user = UserDefaults.standard.string(forKey: "username") ?? ""
    @State private var password = ""
    @State private var selfSigned = UserDefaults.standard.bool(forKey: "allowSelfSigned")
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case server, user, password }

    private var canSubmit: Bool {
        !busy && !server.trimmingCharacters(in: .whitespaces).isEmpty && !user.isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            IPForm {
                Section {
                    VStack(spacing: 12) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .accessibilityHidden(true)
                        Text("InfoPoint")
                            .font(.nunito(.largeTitle, 34, black: true))
                        Text("Einmal mit deinem InfoPoint-Konto anmelden. Danach richtest du Displays auch dann ein, wenn der Server offline ist.")
                            .font(.dm(.subheadline, 14))
                            .foregroundStyle(Theme.fg2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("http://192.168.30.145:8790", text: $server)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .server)
                        .submitLabel(.next)
                        .onSubmit { focus = .user }
                } header: {
                    Text("Server")
                } footer: {
                    Text("Adresse der InfoPoint-WebApp – im Heimnetz oder über Tailscale.")
                }

                Section("Konto") {
                    TextField("Benutzername", text: $user)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .user)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                }

                Section {
                    Toggle("Selbst signiertes Zertifikat erlauben", isOn: $selfSigned)
                } footer: {
                    Text("Nur nötig für die HTTPS-Adresse des Containers (Port 8791).")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button(action: submit) {
                        if busy {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Text("Anmelden")
                        }
                    }
                    .disabled(!canSubmit)
                    .primaryRow()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        busy = true
        error = nil
        Task {
            do {
                try await model.login(server: server, user: user, password: password, selfSigned: selfSigned)
            } catch let e as URLError {
                error = e.code == .serverCertificateUntrusted || e.code == .secureConnectionFailed
                    ? "Zertifikat wird nicht vertraut – „Selbst signiertes Zertifikat erlauben“ einschalten oder http://…:8790 nutzen."
                    : "Server nicht erreichbar (\(e.localizedDescription))"
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
