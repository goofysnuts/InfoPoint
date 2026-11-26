import SwiftUI
import UIKit

enum Route: Hashable {
    case device(String)
    case template(String)
}

// ── Vorschaubild eines Displays im Gehäuse-Rahmen (wie .preview-card .screen) ─
struct DisplayPreview: View {
    @Environment(AppModel.self) private var model
    let firmware: String
    var palette: Int = 0
    var portrait = false
    var more = 0

    @State private var image: UIImage?

    private var name: String { "\(firmware)-\(palette)-\(portrait ? "h" : "q")" }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: AppModel.previewFirmwares.contains(firmware) ? "photo" : FirmwareStyle.symbol(firmware))
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color(white: 0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(3 / 2, contentMode: .fit)
            .background(portrait ? Color.clear : Color(white: 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if more > 0 {
                Text("+\(more) im Wechsel")
                    .font(.dm(.caption, 12, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .padding(8)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x2E2E2E), Color(hex: 0x0E0E0E)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .clear, .black.opacity(0.5)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                }
                .shadow(color: Theme.shDark, radius: 7, x: 6, y: 6)
                .shadow(color: Theme.shLight, radius: 6, x: -5, y: -5)
        }
        .task(id: name) {
            guard AppModel.previewFirmwares.contains(firmware) else { image = nil; return }
            image = await model.previewImage(name)
        }
        .accessibilityLabel("Vorschau \(model.firmwareName(firmware))")
    }
}

// Karte mit Vorschau, Titel und zwei Zeilen (wie .preview-card)
struct PreviewCard<Badges: View>: View {
    let firmware: String
    var palette = 0
    var portrait = false
    var more = 0
    let title: String
    var subtitle: String = ""
    var detail: String = ""
    @ViewBuilder var badges: Badges

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisplayPreview(firmware: firmware, palette: palette, portrait: portrait, more: more)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.nunito(.headline, 17))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    badges
                    Spacer(minLength: 0)
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.dm(.subheadline, 14))
                        .foregroundStyle(Theme.fg2)
                        .lineLimit(1)
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.dm(.footnote, 13))
                        .foregroundStyle(Theme.fg2)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .padding(14)
        .clay()
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// Karte drückt sich federnd ein
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// ── Übersicht ───────────────────────────────────────────────────────────────
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var showNewTemplate = false

    private var visible: [DeviceInfo] { model.devices.filter { $0.mine || model.data?.user.role == "admin" } }

    private var onlineDevices: [DeviceInfo] {
        visible.filter(model.isOnline).sorted {
            if $0.mine != $1.mine { return $0.mine }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    private var ownTemplates: [TemplateInfo] { model.templates.filter(\.mine) }

    private var hello: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 11 ? "Guten Morgen" : h < 18 ? "Hallo" : "Guten Abend"
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(hello), \(model.data?.user.username ?? model.username)!")
                            .font(.nunito(.largeTitle, 32, black: true))
                            .foregroundStyle(Theme.fg)
                        Text("\(onlineDevices.count) von \(visible.count) \(visible.count == 1 ? "Display" : "Displays") online · \(ownTemplates.count) eigene \(ownTemplates.count == 1 ? "Vorlage" : "Vorlagen")")
                            .font(.dm(.body, 16, .medium))
                            .foregroundStyle(Theme.fg2)
                    }
                    .padding(.top, 8)

                    if model.serverReachable == false {
                        OfflineBanner()
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clay(radius: Theme.radiusSm, small: true)
                            .padding(.top, 20)
                    }

                    SectionTitle(text: "Gerade online", systemImage: "display")
                        .padding(.top, 30)
                        .padding(.bottom, 14)
                    if onlineDevices.isEmpty {
                        EmptyCard(systemImage: "display", text: "Gerade ist kein Display online.")
                    } else {
                        LazyVStack(spacing: 22) {
                            ForEach(onlineDevices) { d in
                                NavigationLink(value: Route.device(d.id)) { deviceCard(d) }
                                    .buttonStyle(PressableCardStyle())
                            }
                        }
                    }

                    HStack {
                        SectionTitle(text: "Meine Vorlagen", systemImage: "square.3.layers.3d")
                        Spacer()
                        Button {
                            showNewTemplate = true
                        } label: {
                            Label("Neue Vorlage", systemImage: "plus")
                                .font(.dm(.subheadline, 14, .bold))
                        }
                        .tint(Theme.fg2)
                        .disabled(!model.online || model.catalog.isEmpty)
                    }
                    .padding(.top, 34)
                    .padding(.bottom, 14)
                    if ownTemplates.isEmpty {
                        EmptyCard(systemImage: "square.3.layers.3d", text: "Du hast noch keine eigene Vorlage.")
                    } else {
                        LazyVStack(spacing: 22) {
                            ForEach(ownTemplates) { t in
                                NavigationLink(value: Route.template(t.id)) { templateCard(t) }
                                    .buttonStyle(PressableCardStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
            .refreshable {
                model.discovery.restart()
                await model.syncNow()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { r in
                switch r {
                case .device(let id): DeviceDetailView(deviceId: id)
                case .template(let id): TemplateEditorView(templateId: id)
                }
            }
            .sheet(isPresented: $showNewTemplate) {
                NewTemplateSheet { id in path.append(.template(id)) }
            }
        }
    }

    private func deviceCard(_ d: DeviceInfo) -> some View {
        let running = d.lastSeen?.fw ?? d.firmware
        let members = running == "multi" ? (model.template(d.templateId)?.members ?? []) : []
        let ui = d.ui ?? UiSettings()
        var sub = [d.templateName ?? model.firmwareName(running)]
        if !d.mine, let o = d.ownerName { sub.append(o) }
        var detail = d.lastSeen?.ip ?? ""
        if let rssi = d.lastSeen?.rssi { detail += " · \(rssi) dBm" }
        return PreviewCard(firmware: members.first ?? running, palette: ui.palette, portrait: d.portrait ?? false,
                           more: max(0, members.count - 1), title: d.name,
                           subtitle: sub.joined(separator: " · "), detail: detail) {
            Badge(text: "online", color: Theme.ok)
        }
    }

    private func templateCard(_ t: TemplateInfo) -> some View {
        // Design und Ausrichtung eines Geräts, das die Vorlage nutzt
        let dev = model.devices.first { $0.templateId == t.id }
        let n = t.deviceCount ?? model.devices.filter { $0.templateId == t.id }.count
        let sub = t.members.isEmpty ? model.firmwareName(t.firmware)
            : "\(model.firmwareName(t.firmware)): \(t.members.map(model.firmwareName).joined(separator: ", "))"
        return PreviewCard(firmware: t.members.first ?? t.firmware, palette: dev?.ui?.palette ?? 0,
                           portrait: dev?.portrait ?? false, more: max(0, t.members.count - 1), title: t.name,
                           subtitle: sub, detail: n == 0 ? "auf keinem Gerät" : "\(n) \(n == 1 ? "Gerät" : "Geräte")") {
            if t.shared { Badge(text: "für alle", color: Theme.info, dot: false) }
        }
    }
}

struct EmptyCard: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Tile(systemImage: systemImage, color: Theme.fg2, size: 52)
            Text(text)
                .font(.dm(.body, 15, .medium))
                .foregroundStyle(Theme.fg2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .clay()
    }
}
