import SwiftUI
import AppKit
import Observation

// MARK: - Palette

/// The app's single light palette, taken from the 拾页 design comps
/// (neutral warm-gray surfaces, ink text, blue accent).
enum Palette {
    static let appBg = Color.fromHex("#FFFFFF")
    static let sidebarBg = Color.fromHex("#F7F7F5")
    /// The window's ground (design board ㉗ D): the sidebar sits on it and
    /// the editor floats above it as a white page.
    static let windowGround = Color.fromHex("#EFEEEA")
    /// Fill behind the selected sidebar row, on the window ground.
    static let groundSelectedBg = Color.fromHex("#E2E1DC")
    static let editorBg = Color.fromHex("#FFFFFF")
    static let primaryText = Color.fromHex("#37352F")
    static let secondaryText = Color.fromHex("#55534E")
    static let tertiaryText = Color.fromHex("#73726E")
    /// Default (unselected) stroke color for sidebar and toolbar icons.
    static let iconMuted = Color.fromHex("#8F8E8A")
    /// Pane dividers (sidebar edge, editor header rule).
    static let border = Color.fromHex("#EBEBE9")
    static let codeBlockBg = Color.fromHex("#F7F7F5")
    /// Elevated surface for cards, popovers, selected segments.
    static let surface = Color.fromHex("#FFFFFF")
    /// Fill behind the selected sidebar row.
    static let selectedBg = Color.fromHex("#EBEBE9")
    /// Hairline border for raised controls (the sidebar's New Note button).
    static let controlBorder = Color.fromHex("#E3E3E0")
}

/// Holds the user's accent color. Changing it reskins the whole app (the root
/// view rebuilds via `.id` on `renderKey`).
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var accentHex: String

    private init() {
        // One-time migration from the old multi-theme build: its accents were
        // tied to the removed Paper/Mineral/Bookish/Inky themes, so reset to
        // the new default instead of carrying amber over.
        if UserDefaults.standard.object(forKey: AppSettings.appThemeKey) != nil {
            UserDefaults.standard.removeObject(forKey: AppSettings.appThemeKey)
            AppSettings.accentColorHex = AppSettings.defaultAccentHex
        }
        accentHex = AppSettings.accentColorHex
    }

    var accentColor: Color { Color.fromHex(accentHex) }

    /// A stable key that changes whenever the visible palette changes.
    var renderKey: String { accentHex }

    func setAccent(_ hex: String) {
        accentHex = hex
        AppSettings.accentColorHex = hex
    }

    func applyAppearance() {
        NSApp?.appearance = NSAppearance(named: .aqua)
    }
}

// MARK: - Color tokens

extension Color {
    static var appBg: Color { Palette.appBg }
    static var sidebarBg: Color { Palette.sidebarBg }
    static var windowGround: Color { Palette.windowGround }
    static var groundSelectedBg: Color { Palette.groundSelectedBg }
    static var editorBg: Color { Palette.editorBg }
    static var primaryText: Color { Palette.primaryText }
    static var secondaryText: Color { Palette.secondaryText }
    static var tertiaryText: Color { Palette.tertiaryText }
    static var iconMuted: Color { Palette.iconMuted }
    static var accent: Color { ThemeManager.shared.accentColor }
    static var borderColor: Color { Palette.border }
    static var codeBlockBg: Color { Palette.codeBlockBg }
    /// Elevated surface for cards, popovers, selected segments.
    static var surface: Color { Palette.surface }
    static var selectedBg: Color { Palette.selectedBg }
    static var controlBorder: Color { Palette.controlBorder }
    /// Quietest text: counts beside sidebar folders.
    static var faintText: Color { Color.fromHex("#9B9A97") }
    /// Quietest icon: documents in the sidebar tree.
    static var faintIcon: Color { Color.fromHex("#B4B3AF") }

    static var accentHover: Color { Color.accent.opacity(0.10) }
    static var accentSelected: Color { Color.accent.opacity(0.06) }
    static var cardHover: Color { Color.primaryText.opacity(0.04) }
    static var searchFieldBg: Color { Color.primaryText.opacity(0.03) }
    static var quietSurface: Color { Color.primaryText.opacity(0.025) }
}

extension Font {
    static func notely(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func notelyMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Hex colors

extension Color {
    static func fromHex(_ hex: String) -> Color {
        var cleanHex = hex
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard let value = UInt32(cleanHex, radix: 16) else { return .gray }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}
