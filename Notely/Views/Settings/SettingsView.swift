import AppKit
import ServiceManagement
import SwiftUI

// Settings as a card over the main window (design board ㊳, refining ㉑ B):
// left the four categories, right the selected page. In the Glass theme the
// card is white Liquid Glass over the dimmed window; in the others it is
// solid, the categories on the window's ground and the page on paper. Every
// row changes something real — Export lives in the File menu and About in
// the app menu.

// MARK: - Shared state

@Observable
final class SettingsTabState {
    var selectedTab: SettingsTab = .general
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, editor, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .editor: return "Editor"
        case .shortcuts: return "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "circle.lefthalf.filled"
        case .editor: return "character.cursor.ibeam"
        case .shortcuts: return "command"
        }
    }
}

// MARK: - Modal

/// The settings card. Shown by AppShellView over a dimmed window; esc or a
/// click outside closes it.
struct SettingsModal: View {
    @Environment(SettingsTabState.self) private var state
    @Environment(AppModel.self) private var appModel
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    static let size = CGSize(width: 720, height: 520)
    static let radius: CGFloat = 24

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var isGlass: Bool { themeManager.isGlass }
    private var isDark: Bool { colorScheme == .dark }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.radius, style: .continuous) }

    var body: some View {
        HStack(spacing: 0) {
            navigation
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(state.selectedTab.title)
                        .font(.notely(15, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Spacer()
                    SettingsCloseButton { appModel.showSettings = false }
                }
                .frame(height: 60)
                .padding(.leading, 24)
                .padding(.trailing, 18)
                ScrollView {
                    page
                        .padding(.leading, 24)
                        .padding(.trailing, 22)
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .modifier(SettingsCardSurface(isGlass: isGlass, isDark: isDark, shape: shape))
        // The whole card takes clicks: a click on an empty spot of the glass
        // must not fall through to the dimmed window and close it.
        .contentShape(shape)
        .shadow(color: .black.opacity(isDark ? 0.5 : 0.2), radius: 40, y: 18)
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .background(
            // esc closes the card whichever control has focus.
            Button("Close Settings") { appModel.showSettings = false }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        )
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsNavItem(tab: tab, isSelected: state.selectedTab == tab) {
                    state.selectedTab = tab
                }
            }
            Spacer(minLength: 0)
            Text("Notely \(version)")
                .font(.notely(11.5))
                .foregroundColor(.tertiaryText)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, isGlass ? 12 : 20)
        .padding(.bottom, 12)
        .frame(width: isGlass ? 196 : 206, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background { navBackground }
        .padding([.leading, .vertical], isGlass ? 10 : 0)
    }

    /// Glass: a smaller pane of glass set into the card, like System
    /// Settings' sidebar. Otherwise the window's ground.
    @ViewBuilder private var navBackground: some View {
        if isGlass {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.windowGround.opacity(isDark ? 0.2 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isDark ? Color.white.opacity(0.08) : Color.white, lineWidth: 0.5)
                )
        } else {
            Color.windowGround
        }
    }

    @ViewBuilder private var page: some View {
        switch state.selectedTab {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .editor: EditorSettings()
        case .shortcuts: ShortcutsSettings()
        }
    }
}

/// The card's surface. Glass: native Liquid Glass (macOS 26), clear enough
/// that the note behind shows through, with a whisper of white (or
/// graphite) so the labels stay readable; older systems frost the window's
/// own content instead. Other themes: solid paper.
private struct SettingsCardSurface<S: Shape>: ViewModifier {
    let isGlass: Bool
    let isDark: Bool
    let shape: S

    func body(content: Content) -> some View {
        if isGlass {
            if #available(macOS 26, *) {
                content
                    .background(Color.editorBg.opacity(isDark ? 0.22 : 0.3))
                    .clipShape(shape)
                    .glassEffect(.regular, in: shape)
            } else {
                content
                    .background {
                        ZStack {
                            WithinWindowBlur()
                            Color.editorBg.opacity(isDark ? 0.4 : 0.45)
                        }
                    }
                    .clipShape(shape)
                    .overlay(shape.stroke(isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.9), lineWidth: 1))
            }
        } else {
            content
                .background(Color.editorBg)
                .clipShape(shape)
                .overlay(shape.stroke(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10), lineWidth: 0.5))
        }
    }
}

/// Frosts what the window itself shows behind the card — never the desktop,
/// so no wallpaper color reaches the glass (it stays white or graphite).
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

/// × at the card's top-right corner; esc and a click outside also close.
private struct SettingsCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(isHovering ? .primaryText : .secondaryText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.controlFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close (esc)")
        .accessibilityLabel("Close Settings")
        .onHover { isHovering = $0 }
    }
}

private struct SettingsNavItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13.5))
                    .foregroundColor(isSelected ? .accent : .iconMuted)
                    .frame(width: 18)
                Text(tab.title)
                    .font(.notely(13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.groundSelectedBg : (isHovering ? Color.cardHover : Color.clear))
                    .shadow(color: isSelected ? Color.selectedRowShadow : .clear, radius: 1.5, y: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Building blocks

/// A titled group of rows on a rounded card.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.notely(12, weight: .semibold))
                    .foregroundColor(.tertiaryText)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content()
            }
            // Glass: translucent white (graphite) panes, so the card stays
            // see-through; elsewhere the theme's solid card color.
            .background(ThemeManager.shared.isGlass ? Color.editorBg.opacity(0.5) : Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// One setting: label (and an optional note under it) left, control right.
struct SettingsItem<Control: View>: View {
    let title: String
    var detail: String? = nil
    var isLast = false
    var minHeight: CGFloat = 44
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.notely(13))
                    .foregroundColor(.primaryText)
                if let detail {
                    Text(detail)
                        .font(.notely(11.5))
                        .foregroundColor(.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: minHeight)
        .overlay(alignment: .bottom) { if !isLast { SettingsDivider() } }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Color.primaryText.opacity(0.07)).frame(height: 1)
    }
}

/// A segmented control in the card style: a raised segment on a gray
/// track. The native one fills the selection with the accent, which reads
/// as an alert next to the accent swatches.
struct SettingsSegmented<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var symbols: [Value: String] = [:]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                HStack(spacing: 5) {
                    if let symbol = symbols[option.value] {
                        Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                    }
                    Text(option.label)
                }
                .font(.notely(12.5, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .primaryText : .secondaryText)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? selectedFill : Color.clear)
                        .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 1, y: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { selection = option.value }
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.controlFill))
        .fixedSize()
    }

    private var selectedFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white
    }
}

/// A small raised button (Show in Finder, Change…).
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

// MARK: - General

struct GeneralSettings: View {
    @Environment(FileNoteStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    private var folderPath: String {
        guard let url = store.workspaceURL else { return "No folder open" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Library") {
                SettingsItem(title: "Notes Folder", detail: folderPath, isLast: true, minHeight: 58) {
                    HStack(spacing: 6) {
                        SettingsButton(title: "Show in Finder") {
                            if let url = store.workspaceURL {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                        SettingsButton(title: "Change…") {
                            guard let url = NotesFolderPanel.choose() else { return }
                            store.openWorkspace(at: url)
                            appModel.openNote(nil)
                        }
                    }
                }
            }
            SettingsGroup(title: "Startup") {
                SettingsItem(title: "Open at Login", detail: loginItemError ?? "Start Notely when you log in to your Mac.",
                             isLast: true, minHeight: 54) {
                    Toggle("", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
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

// MARK: - Appearance

struct AppearanceSettings: View {
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage(AppSettings.editorFontKey) private var editorFont = "System"
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultEditorFontSize
    @AppStorage(AppSettings.lineHeightKey) private var lineHeight = 1.7
    @AppStorage(AppSettings.editorWidthKey) private var editorWidth = "medium"

    private let accentColors: [(name: String, hex: String)] = [
        ("Blue", "#1D6FC2"),
        ("Ink", ThemeManager.inkAccentHex),
        ("Green", "#448361"),
        ("Purple", "#9065B0"),
        ("Red", "#C4402F"),
    ]

    private static let modeSymbols: [AppearanceMode: String] = [
        .light: "sun.max", .dark: "moon", .auto: "circle.lefthalf.filled",
    ]

    private var mode: Binding<AppearanceMode> {
        Binding(get: { themeManager.mode }, set: { themeManager.setMode($0) })
    }

    private var lineSpacing: Binding<LineSpacingPreset> {
        Binding(get: { LineSpacingPreset.from(multiplier: lineHeight) },
                set: { lineHeight = $0.multiplier })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Theme") {
                SettingsItem(title: "Appearance") {
                    SettingsSegmented(options: AppearanceMode.allCases.map { ($0.title, $0) },
                                      selection: mode, symbols: Self.modeSymbols)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeTile(theme: theme, isSelected: themeManager.theme == theme) {
                            themeManager.setTheme(theme)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) { SettingsDivider() }
                SettingsItem(title: "Accent Color", isLast: true) {
                    HStack(spacing: 10) {
                        ForEach(accentColors, id: \.hex) { color in
                            AccentDot(hex: color.hex, isSelected: themeManager.accentHex == color.hex) {
                                themeManager.setAccent(color.hex)
                            }
                            .help(color.name)
                            .accessibilityLabel(color.name)
                        }
                    }
                }
            }

            SettingsGroup(title: "Text") {
                SettingsItem(title: "Font") {
                    FontPicker(selection: editorFont) { editorFont = $0 }
                }
                SettingsItem(title: "Size") {
                    SizeStepper(value: $fontSize, range: 12...24)
                }
                SettingsItem(title: "Line Spacing") {
                    SettingsSegmented(options: LineSpacingPreset.allCases.map { ($0.label, $0) },
                                      selection: lineSpacing)
                }
                SettingsItem(title: "Text Width", detail: "Longest line while writing.", isLast: true) {
                    SettingsSegmented(options: [("Narrow", "narrow"), ("Medium", "medium"), ("Wide", "wide")],
                                      selection: $editorWidth)
                }
            }
        }
    }
}

/// A theme drawn as a tiny window: ground with a sidebar, a page with text,
/// in the current light or dark. Glass carries a little white capsule, its
/// toolbar glass.
private struct ThemeTile: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = ThemePalette.palette(theme, dark: colorScheme == .dark)
        let line = Color(nsColor: .hex(p.faintIcon))
        Button(action: action) {
            VStack(spacing: 7) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(line).frame(width: 14, height: 3)
                        Capsule().fill(line.opacity(0.6)).frame(width: 11, height: 3)
                        Capsule().fill(line.opacity(0.6)).frame(width: 11, height: 3)
                    }
                    .padding(.leading, 6)
                    .padding(.top, 4)
                    .frame(width: 26, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color(nsColor: .hex(p.text))).frame(width: 30, height: 4)
                        Capsule().fill(line).frame(height: 3)
                        Capsule().fill(line).frame(width: 34, height: 3)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .hex(p.page)))
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 1, y: 0.5)
                    )
                }
                .padding(.top, 6)
                .padding(.trailing, 6)
                .frame(height: 62)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .hex(p.ground)))
                .overlay(alignment: .topTrailing) {
                    if theme == .glass {
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white)
                            .frame(width: 16, height: 7)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                            .padding(.top, 9)
                            .padding(.trailing, 10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10), lineWidth: 0.5)
                )
                .padding(2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.accent : Color.clear, lineWidth: 2)
                )
                Text(theme.title)
                    .font(.notely(12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primaryText : .secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// − 16 pt + in one rounded pill.
private struct SizeStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Smaller") { value = max(range.lowerBound, value - 1) }
                .disabled(value <= range.lowerBound)
            Text("\(Int(value)) pt")
                .font(.notely(12.5))
                .monospacedDigit()
                .foregroundColor(.primaryText)
                .frame(minWidth: 44)
            stepButton("plus", label: "Larger") { value = min(range.upperBound, value + 1) }
                .disabled(value >= range.upperBound)
        }
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.controlFill))
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.secondaryText)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? fill : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Font picker

/// Searchable picker for the editor body typeface. Lists the system fonts
/// (System / New York / SF Mono — which NSFontManager does not expose as
/// regular families) pinned at the top, followed by every installed family.
struct FontPicker: View {
    let selection: String
    let onSelect: (String) -> Void

    @State private var isPresented = false
    @State private var searchText = ""

    private let pinnedFonts = ["System", "New York", "SF Mono"]

    private var installedFonts: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") && !pinnedFonts.contains($0) }
            .sorted()
    }

    private var visibleFonts: [String] {
        let all = pinnedFonts + installedFonts
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { $0.lowercased().contains(query) }
    }

    private func previewFont(for name: String, size: CGFloat) -> Font {
        Font(WysiwygEngine.resolveFont(name: name, size: size))
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selection)
                    .font(previewFont(for: selection, size: 12.5))
                    .foregroundColor(.primaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.tertiaryText)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.controlFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isPresented) {
            VStack(spacing: 0) {
                TextField("Search fonts", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .padding(10)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleFonts, id: \.self) { name in
                            HStack {
                                Text(name)
                                    .font(previewFont(for: name, size: 13))
                                    .foregroundColor(.primaryText)
                                Spacer()
                                if name == selection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(name)
                                isPresented = false
                            }
                        }
                    }
                }
            }
            .frame(width: 280, height: 380)
        }
    }
}

// MARK: - Editor

struct EditorSettings: View {
    @AppStorage(AppSettings.spellCheckKey) private var spellCheck = AppSettings.defaultSpellCheck
    @AppStorage(AppSettings.smartPunctuationKey) private var smartPunctuation = AppSettings.defaultSmartPunctuation

    var body: some View {
        SettingsGroup(title: "Typing") {
            SettingsItem(title: "Check Spelling", detail: "Underline misspelled words as you type.", minHeight: 54) {
                Toggle("", isOn: $spellCheck)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            SettingsItem(title: "Smart Quotes and Dashes", detail: "Turn \"quotes\" into “quotes” and -- into —.",
                         isLast: true, minHeight: 54) {
                Toggle("", isOn: $smartPunctuation)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Shortcuts

/// The app's real commands (see AppCommands), read-only.
struct ShortcutsSettings: View {
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
        ]),
        ("Formatting", [
            ("Bold", "⌘B"),
            ("Italic", "⌘I"),
            ("Insert Link", "⌘K"),
            ("Toggle To-do", "⌘L"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(groups, id: \.title) { group in
                SettingsGroup(title: group.title) {
                    ForEach(Array(group.items.enumerated()), id: \.offset) { index, item in
                        SettingsItem(title: item.name, isLast: index == group.items.count - 1, minHeight: 36) {
                            HStack(spacing: 3) {
                                ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in
                                    Text(String(key))
                                        .font(.notely(11.5))
                                        .foregroundColor(.secondaryText)
                                        .frame(minWidth: 20, minHeight: 20)
                                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.controlFill))
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.keys)
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
