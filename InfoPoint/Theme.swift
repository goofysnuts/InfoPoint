import SwiftUI
import UIKit

// Design wie die WebApp: „Claymorphism“ – weiche Knete-Optik mit doppelten Schatten,
// große Radien, Pastell-Untergrund, Nunito (Überschriften) + DM Sans (Text), Violett als Akzent.
enum Theme {
    static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1, darkAlpha: CGFloat? = nil) -> Color {
        Color(UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha ?? alpha)
                : UIColor(hex: light, alpha: alpha)
        })
    }

    static let bg = dynamic(0xF4F1FA, 0x141414)
    static let bgElev = dynamic(0xFAF8FD, 0x1B1B1B)
    static let card = dynamic(0xFDFCFF, 0x222222)
    static let card2 = dynamic(0xF6F3FB, 0x2A2A2A)
    static let muted = dynamic(0xECE7F6, 0x333333)
    static let field = dynamic(0xF1EDF8, 0x1A1A1A)
    static let fg = dynamic(0x332F3A, 0xF5F5F5)
    static let fg2 = dynamic(0x635F69, 0xB3B3B3)
    static let fg3 = dynamic(0x8C8794, 0x8A8A8A)
    static let accent = dynamic(0x7C3AED, 0xA78BFA)
    static let accent2 = dynamic(0xA78BFA, 0xC4B5FD)
    static let onAccent = dynamic(0xFFFFFF, 0x141414)
    static let ok = dynamic(0x059669, 0x34D399)
    static let info = dynamic(0x0284C7, 0x7DD3FC)
    static let warn = dynamic(0xB45309, 0xFBBF24)
    static let danger = dynamic(0xDC2626, 0xF87171)
    static let border = dynamic(0x634CA0, 0xFFFFFF, alpha: 0.08, darkAlpha: 0.07)

    // Knete: Außenschatten dunkel (unten rechts) + hell (oben links), innen Glanz + Rundung
    static let shDark = dynamic(0x7460A3, 0x000000, alpha: 0.22, darkAlpha: 0.6)
    static let shLight = dynamic(0xFFFFFF, 0xFFFFFF, alpha: 0.95, darkAlpha: 0.05)
    static let inLight = dynamic(0xFFFFFF, 0xFFFFFF, alpha: 0.9, darkAlpha: 0.07)
    static let inDark = dynamic(0x7460A3, 0x000000, alpha: 0.12, darkAlpha: 0.28)

    static let radius: CGFloat = 28
    static let radiusSm: CGFloat = 18

    static func uiFont(_ name: String, _ size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    // Navigations- und Tableiste
    static func applyAppearance() {
        let large: [NSAttributedString.Key: Any] = [.font: uiFont("Nunito-Black", 34), .foregroundColor: UIColor(fg)]
        let title: [NSAttributedString.Key: Any] = [.font: uiFont("Nunito-ExtraBold", 18), .foregroundColor: UIColor(fg)]

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = large
        nav.titleTextAttributes = title
        let navScrolled = UINavigationBarAppearance()
        navScrolled.configureWithDefaultBackground()
        navScrolled.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        navScrolled.backgroundColor = UIColor(bgElev).withAlphaComponent(0.8)
        navScrolled.shadowColor = .clear
        navScrolled.largeTitleTextAttributes = large
        navScrolled.titleTextAttributes = title
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().standardAppearance = navScrolled
        UINavigationBar.appearance().compactAppearance = navScrolled

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tab.backgroundColor = UIColor(card).withAlphaComponent(0.86)
        tab.shadowColor = .clear
        let item = UITabBarItemAppearance()
        item.normal.titleTextAttributes = [.font: uiFont("DMSans-Bold", 11), .foregroundColor: UIColor(fg2)]
        item.normal.iconColor = UIColor(fg2)
        item.selected.titleTextAttributes = [.font: uiFont("DMSans-Bold", 11), .foregroundColor: UIColor(accent)]
        item.selected.iconColor = UIColor(accent)
        tab.stackedLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UISegmentedControl.appearance().setTitleTextAttributes([.font: uiFont("DMSans-Bold", 13)], for: .normal)
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

enum TextWeight { case regular, medium, bold }

extension Font {
    // Fließtext: DM Sans
    static func dm(_ style: Font.TextStyle, _ size: CGFloat, _ weight: TextWeight = .regular) -> Font {
        let name: String
        switch weight {
        case .regular: name = "DMSans-Regular"
        case .medium: name = "DMSans-Medium"
        case .bold: name = "DMSans-Bold"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    // Überschriften: Nunito
    static func nunito(_ style: Font.TextStyle, _ size: CGFloat, black: Bool = false) -> Font {
        .custom(black ? "Nunito-Black" : "Nunito-ExtraBold", size: size, relativeTo: style)
    }
}

// Pastell-Untergrund der WebApp (hell: Pfirsich, Minze, Lavendel; dunkel: ganz dezent)
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.bg
            if scheme == .dark {
                RadialGradient(colors: [Color.white.opacity(0.035), .clear], center: .center, startRadius: 0, endRadius: 520)
            } else {
                RadialGradient(colors: [Color(hex: 0xFDBCB4).opacity(0.35), .clear],
                               center: UnitPoint(x: 0.92, y: 0.04), startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Color(hex: 0x98FFC8).opacity(0.22), .clear],
                               center: UnitPoint(x: 0.04, y: 0.96), startRadius: 0, endRadius: 460)
                RadialGradient(colors: [Color(hex: 0xC4B5FD).opacity(0.22), .clear],
                               center: .center, startRadius: 0, endRadius: 520)
            }
        }
        .ignoresSafeArea()
    }
}

// ── Knete ───────────────────────────────────────────────────────────────────
struct ClaySurface: View {
    var radius: CGFloat = Theme.radius
    var small = false
    var fill: Color = Theme.card

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(fill)
            // Innenschatten: Glanz oben links, Rundung unten rechts
            .overlay {
                shape
                    .strokeBorder(LinearGradient(colors: [Theme.inLight, .clear, Theme.inDark],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: small ? 3 : 5)
                    .blur(radius: small ? 2 : 3)
                    .clipShape(shape)
            }
            .shadow(color: Theme.shDark, radius: small ? 7 : 13, x: small ? 6 : 12, y: small ? 6 : 12)
            .shadow(color: Theme.shLight, radius: small ? 6 : 11, x: small ? -5 : -10, y: small ? -5 : -10)
    }
}

extension View {
    func clay(radius: CGFloat = Theme.radius, small: Bool = false) -> some View {
        background(ClaySurface(radius: radius, small: small))
    }
}

// Überschrift wie h3 der WebApp (Nunito, Versalien, gesperrt)
struct SectionTitle: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .heavy)) }
            Text(text.uppercased()).tracking(1.0)
        }
        .font(.nunito(.caption, 13))
        .foregroundStyle(Theme.fg2)
        .padding(.leading, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

// Formular / Liste mit Karten im Clay-Stil
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
        .listSectionSpacing(22)
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
        .listSectionSpacing(22)
    }
}

// Plakette wie .badge (ok / info / warn / err)
struct Badge: View {
    let text: String
    var color: Color = Theme.fg2
    var systemImage: String?
    var dot = true

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            } else if dot {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text)
        }
        .font(.dm(.caption, 12, .bold))
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .background(color.opacity(0.16), in: Capsule())
        .lineLimit(1)
        .fixedSize()
    }
}

// Hauptknopf wie .btn.primary: Verlauf, Knete-Schatten, federndes Drücken
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dm(.body, 16, .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent2, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Theme.shDark, radius: 7, x: 6, y: 6)
                    .shadow(color: Theme.shLight, radius: 6, x: -5, y: -5)
            }
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// Nebenknopf wie .btn (Kartenfarbe, kleine Knete)
struct ClayButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dm(.body, 15, .bold))
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(ClaySurface(radius: Theme.radiusSm, small: true))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

extension View {
    // Zeile ohne Karte – für große Knöpfe in Formularen
    func primaryRow() -> some View {
        self.buttonStyle(PrimaryButtonStyle())
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }
}

// Symbol-Kachel wie .tile
struct Tile: View {
    let systemImage: String
    var color: Color = Theme.accent
    var size: CGFloat = 46

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(ClaySurface(radius: size * 0.35, small: true, fill: Theme.card2))
            .accessibilityHidden(true)
    }
}
