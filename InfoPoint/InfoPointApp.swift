import SwiftUI
import BackgroundTasks

@main
struct InfoPointApp: App {
    @State private var model = AppModel()

    init() {
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .font(.jakarta(.body, size: 17))
                .tint(Theme.accent)
        }
        // regelmäßiger Abgleich im Hintergrund: neue Firmwares landen ohne Zutun in der App
        .backgroundTask(.appRefresh(refreshTaskId)) {
            AppModel.scheduleRefresh()
            await model.syncNow()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isLoggedIn {
                MainTabs()
            } else {
                LoginView()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                guard model.isLoggedIn else { return }
                model.discovery.start()
                Task { await model.syncNow() }
            case .background:
                model.discovery.stop()
                AppModel.scheduleRefresh()
            default:
                break
            }
        }
        .onChange(of: model.isLoggedIn) { _, loggedIn in
            if loggedIn { model.discovery.start() } else { model.discovery.stop() }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            DevicesView()
                .tabItem { Label("Geräte", systemImage: "display") }
            TemplatesView()
                .tabItem { Label("Vorlagen", systemImage: "square.grid.2x2") }
            FirmwaresView()
                .tabItem { Label("Firmwares", systemImage: "cpu") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
    }
}
