import SwiftUI
import UIKit

// Farben und Schrift wie in der WebApp ("Dark tech + status green", Plus Jakarta Sans)
enum Theme {
    static func dynamic(_ dark: UInt32, _ light: UInt32, alpha: CGFloat = 1) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: light, alpha: alpha) : UIColor(hex: dark, alpha: alpha) })
    }

    static let bg = dynamic(0x0F172A, 0xF1F5F9)
    static let bgElev = dynamic(0x131C31, 0xFFFFFF)
    static let card = dynamic(0x1B2336, 0xFFFFFF)
    static let field = dynamic(0x2A3448, 0xF1F5F9)
    static let muted = dynamic(0x272F42, 0xE2E8F0)
    static let fg2 = dynamic(0x94A3B8, 0x475569)
    static let accent = dynamic(0x22C55E, 0x16A34A)
    static let info = dynamic(0x38BDF8, 0x0284C7)
    static let warn = dynamic(0xF59E0B, 0xB45309)
    static let danger = dynamic(0xEF4444, 0xDC2626)
    static let border = dynamic(0x94A3B8, 0x0F172A, alpha: 0.16)
    static let onAccent = dynamic(0x0F172A, 0xFFFFFF)

    static let fontFamily = "Plus Jakarta Sans"

    static func uiFont(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let d = UIFontDescriptor(fontAttributes: [
            .family: fontFamily,
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: d, size: size)
    }

    // Navigations- und Tableiste im Stil der WebApp
    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.font: uiFont(32, .heavy)]
        nav.titleTextAttributes = [.font: uiFont(17, .bold)]
        let navScrolled = UINavigationBarAppearance()
        navScrolled.configureWithDefaultBackground()
        navScrolled.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        navScrolled.backgroundColor = UIColor(Theme.bgElev).withAlphaComponent(0.72)
        navScrolled.largeTitleTextAttributes = nav.largeTitleTextAttributes
        navScrolled.titleTextAttributes = nav.titleTextAttributes
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().standardAppearance = navScrolled
        UINavigationBar.appearance().compactAppearance = navScrolled

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        tab.backgroundColor = UIColor(Theme.bgElev).withAlphaComponent(0.72)
        let item = UITabBarItemAppearance()
        item.normal.titleTextAttributes = [.font: uiFont(11, .semibold)]
        item.selected.titleTextAttributes = [.font: uiFont(11, .bold)]
        tab.stackedLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Font {
    static func jakarta(_ style: Font.TextStyle, size: CGFloat) -> Font {
        .custom(Theme.fontFamily, size: size, relativeTo: style)
    }
}

// Hintergrund mit den zwei Farbschimmern der WebApp
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Color(hex: 0x22C55E).opacity(0.10), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: 0x38BDF8).opacity(0.08), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

// Formular / Liste mit Karten wie in der WebApp
struct IPForm<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
    }
}

struct IPList<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        List {
            Group { content }
                .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
    }
}

// Statusplakette wie .badge in der WebApp
struct Badge: View {
    let text: String
    var color: Color = Theme.fg2
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text)
        }
        .font(.jakarta(.caption, size: 12).weight(.bold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

// Hauptknopf wie .btn.primary in der WebApp
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.jakarta(.body, size: 16).weight(.bold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.accent.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    // Zeile ohne Karte – für große Knöpfe in Formularen
    func primaryRow() -> some View {
        self.buttonStyle(PrimaryButtonStyle())
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }
}
