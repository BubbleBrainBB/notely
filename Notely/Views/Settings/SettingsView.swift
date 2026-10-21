import AppKit
import ServiceManagement
import SwiftUI

// Settings as one sheet of paper over the dimmed window (design board ㊶,
// direction ㊵ A): read top to bottom — Look, Writing, Library — with the
// group names in an italic margin and the choices as plain words, the
// chosen one underlined in the accent. No cards, pills or switches. The
// keyboard shortcuts are the same sheet slid over. Every row changes
// something real — Export lives in the File menu and About in the app menu.

// MARK: - Shared state

@Observable
final class SettingsTabState {
    var page: SettingsPage = .settings
}

enum SettingsPage {
    case settings, shortcuts
}

// MARK: - Modal

/// The settings sheet. Shown by AppShellView over a dimmed window; esc, ⌘.
/// or a click outside closes it.
struct SettingsModal: View {
    @Environment(SettingsTabState.self) private var state
    @Environment(AppModel.self) private var appModel
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    static let width: CGFloat = 600
    static let radius: CGFloat = 14

    private var isDark: Bool { colorScheme == .dark }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.radius, style: .continuous) }

    var body: some View {
        GeometryReader { proxy in
            // As tall as its content, never closer than 40 to the window's
            // edges; past that the sheet scrolls inside.
            sheet(maxHeight: max(260, proxy.size.height - 80))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { state.page = .settings }
    }

    private func sheet(maxHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            switch state.page {
            case .settings:
                SettingsPageView(maxHeight: maxHeight, close: close) { show(.shortcuts) }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .shortcuts:
                ShortcutsPageView(maxHeight: maxHeight) { show(.settings) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: Self.width)
        .modifier(SettingsSheetSurface(isGlass: themeManager.isGlass, isDark: isDark, shape: shape))
        // The whole sheet takes clicks: a click on an empty spot must not
        // fall through to the dimmed window and close it.
        .contentShape(shape)
        .shadow(color: .black.opacity(isDark ? 0.45 : 0.16), radius: 40, y: 30)
        .background {
            // esc and ⌘. close the sheet whichever control has focus.
            ZStack {
                Button("Close Settings", action: close).keyboardShortcut(.cancelAction)
                Button("Close Settings", action: close).keyboardShortcut(".", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func show(_ page: SettingsPage) {
        withAnimation(.easeInOut(duration: 0.24)) { state.page = page }
    }

    private func close() {
        appModel.showSettings = false
    }
}

/// The sheet's paper. Glass: frosted white (graphite) Liquid Glass — the
/// window behind shows through, the text still sits on white — with a
/// white highlight edge; older systems frost the window's own content.
/// Other themes: the theme's page color with a faint edge.
private struct SettingsSheetSurface<S: InsettableShape>: ViewModifier {
    let isGlass: Bool
    let isDark: Bool
    let shape: S

    func body(content: Content) -> some View {
        if isGlass {
            if #available(macOS 26, *) {
                content
                    .background(Color.editorBg.opacity(isDark ? 0.45 : 0.6))
                    .clipShape(shape)
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(isDark ? 0.12 : 0.75), lineWidth: 1))
            } else {
                content
                    .background {
                        ZStack {
                            WithinWindowBlur()
                            Color.editorBg.opacity(isDark ? 0.55 : 0.7)
                        }
                    }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(isDark ? 0.14 : 0.9), lineWidth: 1))
            }
        } else {
            content
                .background(Color.editorBg)
                .clipShape(shape)
                .overlay(shape.strokeBorder(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05), lineWidth: 1))
        }
    }
}

/// Frosts what the window itself shows behind the sheet — never the
/// desktop, so no wallpaper color reaches the glass.
private struct WithinWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Pages

/// A page of the sheet: a fixed header, then the content — at its own
/// height when it fits, otherwise in a scroll view whose bottom edge fades
/// to say there is more, with the editor's slim scroller.
private struct SheetPage<Header: View, Content: View>: View {
    let maxHeight: CGFloat
    var topPadding: CGFloat = 34
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        HeightCap(maxHeight: maxHeight) {
            VStack(spacing: 0) {
                header()
                    .padding(.top, topPadding)
                    .padding(.horizontal, 44)
                ViewThatFits(in: .vertical) {
                    paddedContent
                    ScrollView(.vertical) {
                        paddedContent
                            .background(QuietScrollerInstaller())
                    }
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 32)
                        }
                    }
                }
            }
        }
    }

    private var paddedContent: some View {
        content()
            .padding(.horizontal, 44)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Offers its content at most `maxHeight` and takes the height the content
/// asks for — a plain `.frame(maxHeight:)` would grow to the cap.
private struct HeightCap: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = min(proposal.height ?? maxHeight, maxHeight)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private struct SettingsPageView: View {
    let maxHeight: CGFloat
    let close: () -> Void
    let showShortcuts: () -> Void

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        SheetPage(maxHeight: maxHeight) {
            HStack(alignment: .firstTextBaseline) {
                Text("Settings")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .tracking(-0.2)
                    .foregroundColor(.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                EscButton(action: close)
            }
            .padding(.bottom, 20)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSection(title: "Look", labelTop: 19) { LookSettings() }
                SettingsSection(title: "Writing", labelTop: 12) { WritingSettings() }
                SettingsSection(title: "Library", labelTop: 10, isLast: true) { LibrarySettings() }
                HStack(alignment: .firstTextBaseline) {
                    SettingsLink(title: "Keyboard shortcuts →", size: 12, action: showShortcuts)
                    Spacer()
                    Text("Notely \(version)")
                        .font(.notely(12))
                        .foregroundColor(.faintIcon)
                }
                .padding(.top, 20)
            }
        }
    }
}

private struct ShortcutsPageView: View {
    let maxHeight: CGFloat
    let back: () -> Void

    var body: some View {
        SheetPage(maxHeight: maxHeight, topPadding: 26) {
            VStack(alignment: .leading, spacing: 6) {
                SettingsLink(title: "← Settings", size: 12, action: back)
                Text("Keyboard Shortcuts")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundColor(.primaryText)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
        } content: {
            ShortcutsSettings()
        }
    }
}

// MARK: - Building blocks

/// Separator lines on the sheet: between rows, and the stronger one between
/// groups. Drawn in the text color so they step down with dark mode.
private extension Color {
    static var settingsRowLine: Color { Color.primaryText.opacity(0.07) }
    static var settingsGroupLine: Color { Color.primaryText.opacity(0.11) }
}

/// A group: its name in italics in the left margin, level with the first
/// row's label, and a full-width hairline after it.
private struct SettingsSection<Content: View>: View {
    let title: String
    /// Where the name sits so it lines up with the first row's label.
    var labelTop: CGFloat = 12
    var isLast = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                Text(title)
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundColor(.faintText)
                    .frame(width: 92, alignment: .leading)
                    .padding(.top, labelTop)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) { content() }
            }
            if !isLast {
                Rectangle().fill(Color.settingsGroupLine).frame(height: 1).padding(.vertical, 14)
            }
        }
    }
}

/// One setting: its label (and a note under it) left, the choice right.
private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var height: CGFloat = 42
    var isLast = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.notely(13.5))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.notely(11.5))
                        .foregroundColor(.faintText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, detail == nil ? 0 : 6)
        .frame(minHeight: detail == nil ? height : max(height, 50))
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(Color.settingsRowLine).frame(height: 1) }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Plain words, the chosen one dark and underlined in the accent. A click
/// takes effect at once; the new line fades in as the old fades out.
/// With keyboard navigation, Tab reaches the row and ←/→ change the choice;
/// focus shows as a dashed accent line under the chosen word.
private struct TextChoice<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var accessibilityLabel: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 18) {
            ForEach(options, id: \.value) { option in
                ChoiceWord(label: option.label, isSelected: option.value == selection,
                           showsFocus: isFocused) {
                    selection = option.value
                }
            }
        }
        .fixedSize()
        .focusable(interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        guard let index = options.firstIndex(where: { $0.value == selection }) else { return .ignored }
        let next = index + delta
        guard options.indices.contains(next) else { return .handled }
        selection = options[next].value
        return .handled
    }
}

private struct ChoiceWord: View {
    let label: String
    let isSelected: Bool
    let showsFocus: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Text(label)
            .font(.notely(13))
            .foregroundColor(isSelected ? .primaryText : (isHovering ? .secondaryText : .faintText))
            .overlay(alignment: .bottom) {
                underline
                    .frame(height: 1.5)
                    .offset(y: 4)
                    .opacity(isSelected ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { isHovering = $0 }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { action() }
    }

    @ViewBuilder private var underline: some View {
        if showsFocus {
            Line()
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
        } else {
            Rectangle().fill(Color.accent)
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

/// On / Off as two words, in place of a switch.
private struct OnOffChoice: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        TextChoice(options: [("On", true), ("Off", false)], selection: $isOn, accessibilityLabel: label)
    }
}

/// A text link: gray for the quiet actions, the accent for the main one.
private struct SettingsLink: View {
    let title: String
    var size: CGFloat = 12.5
    var isPrimary = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.notely(size))
                .foregroundColor(color)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovering = $0 }
    }

    private var color: Color {
        if isPrimary { return Color.accent.opacity(isHovering ? 0.8 : 1) }
        return isHovering ? .primaryText : .tertiaryText
    }
}

/// “esc” at the sheet's top right; a light fill on hover.
private struct EscButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("esc")
                .font(.notely(12))
                .foregroundColor(isHovering ? .secondaryText : .faintText)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.cardHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close (esc)")
        .accessibilityLabel("Close Settings")
        .onHover { isHovering = $0 }
    }
}

/// A small raised button (the memo editor's Cancel / Save).
struct SettingsButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.notely(12.5))
                .foregroundColor(.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(isHovering ? 0.16 : 0.12) : (isHovering ? Color.quietSurface : Color.white))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovering = $0 }
    }
}

// MARK: - Look

private struct LookSettings: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var hoveredAccent: String?

    private let accentColors: [(name: String, hex: String)] = [
        ("Blue", "#1D6FC2"),
        ("Ink", ThemeManager.inkAccentHex),
        ("Green", "#448361"),
        ("Purple", "#9065B0"),
        ("Red", "#C4402F"),
    ]

    private var mode: Binding<AppearanceMode> {
        Binding(get: { themeManager.mode }, set: { themeManager.setMode($0) })
    }

    var body: some View {
        SettingRow(title: "Theme", height: 56) {
            HStack(spacing: 16) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeSwatch(theme: theme, isSelected: themeManager.theme == theme) {
                        themeManager.setTheme(theme)
                    }
                }
            }
        }
        SettingRow(title: "Mode") {
            TextChoice(options: AppearanceMode.allCases.map { ($0 == .auto ? "Match System" : $0.title, $0) },
                       selection: mode, accessibilityLabel: "Mode")
        }
        SettingRow(title: "Accent", isLast: true) {
            HStack(spacing: 11) {
                // The hovered dot's name, quietly to its left.
                Text(hoveredAccent ?? "")
                    .font(.notely(11.5))
                    .foregroundColor(.faintText)
                    .padding(.trailing, 3)
                    .animation(nil, value: hoveredAccent)
                ForEach(accentColors, id: \.hex) { color in
                    AccentDot(hex: color.hex, isSelected: themeManager.accentHex == color.hex) {
                        themeManager.setAccent(color.hex)
                    }
                    .onHover { hoveredAccent = $0 ? color.name : (hoveredAccent == color.name ? nil : hoveredAccent) }
                    .accessibilityLabel(color.name)
                }
            }
        }
    }
}

/// A theme as a tiny desk: the window's ground with a page floating on its
/// right, in the current light or dark. The name sits underneath.
private struct ThemeSwatch: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let p = ThemePalette.palette(theme, dark: dark)
        let swatch = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .trailing) {
                    ground(p, dark: dark)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(nsColor: .hex(p.page)).opacity(theme == .glass ? 0.72 : 1))
                        .frame(width: 21)
                        .padding(3)
                }
                .frame(width: 36, height: 26)
                .clipShape(swatch)
                .overlay {
                    if isSelected {
                        // 1.5 of paper, then 1.5 of accent, outside the swatch.
                        swatch.strokeBorder(Color.editorBg, lineWidth: 1.5).padding(-1.5)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accent, lineWidth: 1.5).padding(-3)
                    } else {
                        swatch.strokeBorder(Color.primaryText.opacity(dark ? 0.14 : 0.08), lineWidth: 1)
                    }
                }
                Text(theme.title)
                    .font(.notely(11))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(isSelected ? .primaryText : .faintText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Glass's ground is whatever shows through the window: a soft wash.
    @ViewBuilder private func ground(_ p: ThemePalette, dark: Bool) -> some View {
        if theme == .glass {
            LinearGradient(colors: dark ? [Color(nsColor: .hex(0x2B3038)), Color(nsColor: .hex(0x302C35))]
                                        : [Color(nsColor: .hex(0xE3EAF1)), Color(nsColor: .hex(0xF5F2F7))],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color(nsColor: .hex(p.ground))
        }
    }
}

private struct AccentDot: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    /// Ink is the theme's own ink, so its dot follows light and dark.
    private var fill: Color {
        hex == ThemeManager.inkAccentHex ? .primaryText : Color.fromHex(hex)
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: 14, height: 14)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(fill, lineWidth: 1.5).frame(width: 21, height: 21)
                    }
                }
                .frame(width: 21, height: 21)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -3.5)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Writing

private struct WritingSettings: View {
    @AppStorage(AppSettings.editorFontKey) private var editorFont = "System"
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultEditorFontSize
    @AppStorage(AppSettings.lineHeightKey) private var lineHeight = 1.7
    @AppStorage(AppSettings.editorWidthKey) private var editorWidth = "medium"
    @AppStorage(AppSettings.spellCheckKey) private var spellCheck = AppSettings.defaultSpellCheck
    @AppStorage(AppSettings.smartPunctuationKey) private var smartPunctuation = AppSettings.defaultSmartPunctuation

    private var lineSpacing: Binding<LineSpacingPreset> {
        Binding(get: { LineSpacingPreset.from(multiplier: lineHeight) },
                set: { lineHeight = $0.multiplier })
    }

    var body: some View {
        SettingRow(title: "Typeface") {
            FontPicker(selection: editorFont) { editorFont = $0 }
        }
        SettingRow(title: "Size") {
            SizeStepper(value: $fontSize, range: 12...24)
        }
        SettingRow(title: "Line spacing") {
            TextChoice(options: LineSpacingPreset.allCases.map { ($0.label, $0) },
                       selection: lineSpacing, accessibilityLabel: "Line spacing")
        }
        SettingRow(title: "Line length") {
            TextChoice(options: [("Narrow", "narrow"), ("Medium", "medium"), ("Wide", "wide")],
                       selection: $editorWidth, accessibilityLabel: "Line length")
        }
        SettingRow(title: "Check spelling") {
            OnOffChoice(isOn: $spellCheck, label: "Check spelling")
        }
        SettingRow(title: "Smart quotes and dashes", detail: "\"quotes\" → “quotes”, -- → —", isLast: true) {
            OnOffChoice(isOn: $smartPunctuation, label: "Smart quotes and dashes")
        }
    }
}

/// − 16 +: two round, see-through buttons that fill on hover.
private struct SizeStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 4) {
            RoundStepButton(symbol: "minus", label: "Smaller", isEnabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            Text("\(Int(value))")
                .font(.notely(13.5))
                .monospacedDigit()
                .foregroundColor(.primaryText)
                .frame(minWidth: 24)
                .accessibilityLabel("Size \(Int(value))")
            RoundStepButton(symbol: "plus", label: "Larger", isEnabled: value < range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .padding(.trailing, -3)
    }
}

private struct RoundStepButton: View {
    let symbol: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isHovering && isEnabled ? Color.cardHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
    }
}

// MARK: - Font picker

/// The editor's typeface, written in itself, with a small ▾. Opens a
/// searchable list: System / New York / SF Mono (which NSFontManager does
/// not expose as regular families) first, then every installed family, each
/// in its own face.
struct FontPicker: View {
    let selection: String
    let onSelect: (String) -> Void

    @State private var isPresented = false
    @State private var searchText = ""
    @State private var hovered: String?

    private let pinnedFonts = ["System", "New York", "SF Mono"]

    private var installedFonts: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") && !pinnedFonts.contains($0) }
            .sorted()
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func matching(_ fonts: [String]) -> [String] {
        query.isEmpty ? fonts : fonts.filter { $0.lowercased().contains(query) }
    }

    private func previewFont(for name: String, size: CGFloat) -> Font {
        Font(WysiwygEngine.resolveFont(name: name, size: size))
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(selection)
                    .font(previewFont(for: selection, size: selection == "SF Mono" ? 13 : 14))
                    .foregroundColor(.primaryText)
                Text(isPresented ? "▴" : "▾")
                    .font(.system(size: 10.5))
                    .foregroundColor(.faintText)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Typeface, \(selection)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { list }
    }

    private var list: some View {
        VStack(spacing: 6) {
            TextField("Search fonts", text: $searchText)
                .textFieldStyle(.plain)
                .font(.notely(12.5))
                .foregroundColor(.primaryText)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.searchFieldBg))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let pinned = matching(pinnedFonts)
                    let installed = matching(installedFonts)
                    ForEach(pinned, id: \.self) { row($0) }
                    if !pinned.isEmpty && !installed.isEmpty {
                        Rectangle().fill(Color.settingsRowLine).frame(height: 1)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                    }
                    ForEach(installed, id: \.self) { row($0) }
                }
                .background(QuietScrollerInstaller())
            }
        }
        .padding(8)
        .frame(width: 250, height: 340)
        // The popover's own material follows the system's light or dark,
        // not Notely's mode; the theme's page keeps the text readable.
        .presentationBackground(Color.editorBg)
    }

    private func row(_ name: String) -> some View {
        let isSelected = name == selection
        return HStack {
            Text(name)
                .font(previewFont(for: name, size: name == "SF Mono" ? 13 : 14))
                .foregroundColor(.primaryText)
                .lineLimit(1)
            Spacer()
            if isSelected {
                Text("✓")
                    .font(.notely(12))
                    .foregroundColor(.accent)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accent.opacity(0.08) : (hovered == name ? Color.cardHover : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? name : (hovered == name ? nil : hovered) }
        .onTapGesture {
            onSelect(name)
            isPresented = false
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Library

private struct LibrarySettings: View {
    @Environment(FileNoteStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    private var folderName: String {
        store.workspaceURL?.lastPathComponent ?? "No folder open"
    }

    private var folderPath: String? {
        guard let url = store.workspaceURL else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        SettingRow(title: folderName, detail: folderPath) {
            HStack(spacing: 14) {
                if let url = store.workspaceURL {
                    SettingsLink(title: "Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                SettingsLink(title: "Change…", isPrimary: true) {
                    guard let url = NotesFolderPanel.choose() else { return }
                    store.openWorkspace(at: url)
                    appModel.openNote(nil)
                }
            }
        }
        SettingRow(title: "Open at login", detail: loginItemError, isLast: true) {
            OnOffChoice(isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin), label: "Open at login")
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        guard enabled != openAtLogin else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change this: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Shortcuts

/// The app's real commands (see AppCommands), read-only. Keys are plain
/// faint text, no keycaps.
private struct ShortcutsSettings: View {
    private let groups: [(title: String, items: [(name: String, keys: String)])] = [
        ("Notes", [
            ("New Note", "⌘N"),
            ("New Window", "⇧⌘N"),
            ("Open Folder…", "⌘O"),
            ("Search Notes", "⇧⌘F"),
            ("Toggle Sidebar", "⌥⌘S"),
            ("Settings", "⌘,"),
        ]),
        ("Tabs", [
            ("New Tab", "⌘T"),
            ("Close Tab", "⌘W"),
            ("Reopen Closed Tab", "⇧⌘T"),
            ("Show Next Tab", "⌃⇥"),
            ("Show Previous Tab", "⌃⇧⇥"),
            ("Pin / Unpin Tab", "⌥⌘P"),
        ]),
        ("Format", [
            ("Bold", "⌘B"),
            ("Italic", "⌘I"),
            ("Insert Link", "⌘K"),
            ("Toggle To-do", "⌘L"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups, id: \.title) { group in
                HStack(alignment: .top, spacing: 16) {
                    Text(group.title)
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundColor(.faintText)
                        .frame(width: 80, alignment: .leading)
                        .padding(.top, 7)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.offset) { index, item in
                            HStack {
                                Text(item.name)
                                    .font(.notely(12.5))
                                    .foregroundColor(.primaryText)
                                Spacer()
                                Text(item.keys)
                                    .font(.notely(12.5))
                                    .tracking(1.5)
                                    .foregroundColor(.faintText)
                            }
                            .frame(height: 30)
                            .overlay(alignment: .bottom) {
                                if index < group.items.count - 1 {
                                    Rectangle().fill(Color.settingsRowLine).frame(height: 1)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Export (File menu)

enum NoteExporter {
    /// Writes every note as a Markdown file into a folder the user picks.
    static func exportAll(_ notes: [FileNote]) {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        for note in notes {
            let title = note.title.isEmpty ? note.filename : note.title
            let safe = title
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespaces)
            let name = (safe.isEmpty ? "Untitled" : safe) + ".md"
            try? note.content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }
}
