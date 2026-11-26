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
                .font(.dm(.body, 16, .medium))
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
    @Environment(AppModel.self) private var model
    private var isAdmin: Bool { model.data?.user.role == "admin" }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Übersicht", systemImage: "house") }
            DevicesView()
                .tabItem { Label("Geräte", systemImage: "display") }
            TemplatesView()
                .tabItem { Label("Vorlagen", systemImage: "square.3.layers.3d") }
            WifiView()
                .tabItem { Label("WLAN", systemImage: "wifi") }
            SettingsView()
                .tabItem { Label(isAdmin ? "Einstellungen" : "Konto", systemImage: isAdmin ? "slider.horizontal.3" : "person.crop.circle") }
        }
    }
}
