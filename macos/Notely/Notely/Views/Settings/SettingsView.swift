import SwiftUI
import AppKit

// MARK: - Shared settings tab state

@Observable
final class SettingsTabState {
    var selectedTab: SettingsTab = .general
}

// MARK: - Settings tab list (left of the settings content)

struct SettingsTabBar: View {
    @Environment(SettingsTabState.self) var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primaryText)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

            VStack(spacing: 1) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsTabItem(
                        tab: tab,
                        isSelected: state.selectedTab == tab
                    ) {
                        state.selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .frame(width: 220)
        .background(Color.editorBg)
    }
}

// MARK: - Settings content

struct SettingsContent: View {
    @Environment(SettingsTabState.self) var state

    var body: some View {
        ScrollView {
            Group {
                switch state.selectedTab {
                case .general:    GeneralSettings()
                case .appearance: AppearanceSettings()
                case .editor:     EditorSettings()
                case .shortcuts:  ShortcutsSettings()
                case .cloud:      CloudSettings()
                case .exportTab:  ExportSettings()
                case .about:      AboutSettings()
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 40)
            .padding(.bottom, 60)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(Color.editorBg)
        .navigationSplitViewColumnWidth(min: 560, ideal: 760)
    }
}

// MARK: - Tab definitions

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, editor, shortcuts, cloud, exportTab, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .editor: return "Editor"
        case .shortcuts: return "Shortcuts"
        case .cloud: return "iCloud Sync"
        case .exportTab: return "Export"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "square.3.layers.3d"
        case .appearance: return "sun.max"
        case .editor: return "pencil"
        case .shortcuts: return "keyboard"
        case .cloud: return "icloud"
        case .exportTab: return "square.and.arrow.down"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Tab item

struct SettingsTabItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    /// Visual state of a tab row. Selection wins over hover. Pure + testable.
    enum Highlight {
        case selected, hover, none
        static func resolve(isSelected: Bool, isHovering: Bool) -> Highlight {
            if isSelected { return .selected }
            if isHovering { return .hover }
            return .none
        }
    }

    private var highlight: Highlight {
        Highlight.resolve(isSelected: isSelected, isHovering: isHovering)
    }

    private var backgroundColor: Color {
        switch highlight {
        case .selected: return Color.accent.opacity(0.10)
        case .hover: return Color.primaryText.opacity(0.06)
        case .none: return .clear
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundColor(isSelected ? .accent : .secondaryText)
                Text(tab.title)
                    .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .accent : .primaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            // Fill the column width and make the WHOLE row (incl. the trailing
            // empty space) hittable, not just the icon + label.
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: highlight)
    }
}

extension SettingsTabItem.Highlight: Equatable {}

// MARK: - Reusable building blocks

/// Panel heading: large title + muted subtitle, with bottom spacing baked in.
struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.2)
                .foregroundColor(.primaryText)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primaryText.opacity(0.06))
            .frame(height: 1)
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primaryText)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control()
        }
    }
}

struct SettingsToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 13)
                .fill(isOn ? Color.accent : Color.primaryText.opacity(0.12))
                .frame(width: 44, height: 26)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .offset(x: isOn ? 9 : -9)
                        .animation(.easeInOut(duration: 0.15), value: isOn)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsStepper: View {
    let value: Int
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Text("\(value)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primaryText)
                .frame(width: 44)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// iOS/macOS-style segmented control with a white selected pill.
struct SettingsSegmented: View {
    let options: [(label: String, value: String)]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                Text(opt.label)
                    .font(.system(size: 13, weight: selection == opt.value ? .medium : .regular))
                    .foregroundColor(selection == opt.value ? .primaryText : .secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selection == opt.value ? Color.surface : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(opt.value) }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primaryText.opacity(0.05))
        )
    }
}

/// A small white "chip" button used for dropdown-like and path controls.
struct ChipButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1)
                )
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.surface))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keyboard shortcut chips (Shortcuts)

struct Keycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondaryText)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primaryText.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primaryText.opacity(0.07), lineWidth: 1))
    }
}

struct ShortcutGroup: View {
    let title: String
    let items: [(name: String, keys: [String])]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.tertiaryText)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack {
                        Text(item.name)
                            .font(.system(size: 14))
                            .foregroundColor(.primaryText)
                        Spacer(minLength: 12)
                        HStack(spacing: 5) {
                            ForEach(Array(item.keys.enumerated()), id: \.offset) { _, k in
                                Keycap(key: k)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if idx < items.count - 1 {
                        Rectangle().fill(Color.primaryText.opacity(0.06)).frame(height: 1)
                    }
                }
            }
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1))
        }
    }
}

// MARK: - General tab

struct GeneralSettings: View {
    @Environment(FileNoteStore.self) private var store
    @State private var launchAtLogin: Bool = AppSettings.launchAtLogin
    @State private var autoUpdates: Bool = AppSettings.autoUpdates

    /// The currently opened workspace folder, shown with `~` for the home dir.
    private var folderPath: String {
        guard let url = store.workspaceURL else { return "No folder open" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "General", subtitle: "Configure how the app behaves.")

            SettingsRow(title: "Notes Folder", subtitle: "The folder you opened. New notes are saved here.") {
                ChipButton {
                    if let url = store.workspaceURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(folderPath)
                            .font(.system(size: 14))
                            .foregroundColor(.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10))
                            .foregroundColor(.tertiaryText)
                    }
                }
                .help("Reveal in Finder")
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Launch at Login", subtitle: "Open the app when you start your Mac.") {
                SettingsToggle(isOn: launchAtLogin) {
                    launchAtLogin.toggle()
                    AppSettings.launchAtLogin = launchAtLogin
                }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Automatic Updates", subtitle: "Check for new versions automatically.") {
                SettingsToggle(isOn: autoUpdates) {
                    autoUpdates.toggle()
                    AppSettings.autoUpdates = autoUpdates
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Font picker

/// Searchable picker for the editor body typeface. Lists the system fonts
/// (System / New York / SF Mono — which NSFontManager does not expose as
/// regular families) pinned at the top, followed by every font family
/// installed on the machine. No fonts are bundled with the app, so every
/// listed option resolves to a real, installed typeface.
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

    private func previewFont(for name: String) -> Font {
        switch name {
        case "System", "": return .system(size: 14)
        case "SF Mono": return .system(size: 14, design: .monospaced)
        case "New York": return .system(size: 14, design: .serif)
        default: return .custom(name, size: 14)
        }
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selection)
                    .font(previewFont(for: selection))
                    .foregroundColor(.primaryText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1)
            )
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.surface))
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
                                    .font(previewFont(for: name))
                                    .foregroundColor(.primaryText)
                                Spacer()
                                if name == selection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color.accentColor)
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

// MARK: - Appearance tab

struct AppearanceSettings: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var editorFont: String = AppSettings.editorFont
    @State private var editorWidth: String = AppSettings.editorWidth
    @State private var lineSpacing: String = LineSpacingPreset.from(multiplier: AppSettings.editorLineHeight).rawValue

    private let accentColors: [(name: String, hex: String)] = [
        ("Blue", "#1D6FC2"),
        ("Ink", "#37352F"),
        ("Green", "#448361"),
        ("Purple", "#9065B0"),
        ("Red", "#C4402F"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Appearance", subtitle: "Personalize how your notes look.")

            SettingsRow(title: "Accent Color", subtitle: "Highlight color for selections and links.") {
                HStack(spacing: 8) {
                    ForEach(accentColors, id: \.hex) { color in
                        Circle()
                            .fill(Color.fromHex(color.hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().strokeBorder(Color.surface, lineWidth: themeManager.accentHex == color.hex ? 2 : 0)
                            )
                            .overlay(
                                Circle().strokeBorder(Color.fromHex(color.hex), lineWidth: themeManager.accentHex == color.hex ? 2 : 0)
                                    .padding(-2)
                            )
                            .overlay(
                                themeManager.accentHex == color.hex
                                ? Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                                : nil
                            )
                            .contentShape(Circle())
                            .onTapGesture {
                                themeManager.setAccent(color.hex)
                            }
                    }
                }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Editor Font", subtitle: "Typeface used for note body text.") {
                FontPicker(selection: editorFont) { fontName in
                    editorFont = fontName
                    AppSettings.editorFont = fontName
                }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Editor Width", subtitle: "Maximum line length while writing.") {
                SettingsSegmented(
                    options: [("Narrow", "narrow"), ("Medium", "medium"), ("Wide", "wide")],
                    selection: editorWidth
                ) { editorWidth = $0; AppSettings.editorWidth = $0 }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Line Spacing", subtitle: "Vertical rhythm between lines of text.") {
                SettingsSegmented(
                    options: LineSpacingPreset.allCases.map { ($0.label, $0.rawValue) },
                    selection: lineSpacing
                ) { value in
                    lineSpacing = value
                    if let preset = LineSpacingPreset(rawValue: value) {
                        AppSettings.editorLineHeight = preset.multiplier
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Editor tab

struct EditorSettings: View {
    @State private var spellCheck = AppSettings.spellCheck
    @State private var autoPair = AppSettings.autoPair
    @State private var smartPunctuation = AppSettings.smartPunctuation
    @State private var markdownSyntax = AppSettings.markdownSyntax
    @State private var tabSize = AppSettings.tabSize
    @State private var wordWrap = AppSettings.wordWrap
    @State private var typewriter = AppSettings.typewriter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Editor", subtitle: "Control writing and Markdown behavior.")

            SettingsRow(title: "Spell Check", subtitle: "Underline misspelled words as you type.") {
                SettingsToggle(isOn: spellCheck) { spellCheck.toggle(); AppSettings.spellCheck = spellCheck }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Auto-pair Brackets & Quotes", subtitle: "Automatically close (), [], and quotes.") {
                SettingsToggle(isOn: autoPair) { autoPair.toggle(); AppSettings.autoPair = autoPair }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Smart Punctuation", subtitle: "Convert straight quotes and dashes as you write.") {
                SettingsToggle(isOn: smartPunctuation) { smartPunctuation.toggle(); AppSettings.smartPunctuation = smartPunctuation }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Markdown Syntax", subtitle: "When to reveal raw Markdown markers.") {
                SettingsSegmented(
                    options: [("Always", "always"), ("On Focus", "focus"), ("Hidden", "hidden")],
                    selection: markdownSyntax
                ) { markdownSyntax = $0; AppSettings.markdownSyntax = $0 }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Tab Size", subtitle: "Spaces inserted per indent level.") {
                SettingsStepper(
                    value: tabSize,
                    onDecrement: { if tabSize > 2 { tabSize -= 1; AppSettings.tabSize = tabSize } },
                    onIncrement: { if tabSize < 8 { tabSize += 1; AppSettings.tabSize = tabSize } }
                )
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Word Wrap", subtitle: "Wrap long lines to the editor width.") {
                SettingsToggle(isOn: wordWrap) { wordWrap.toggle(); AppSettings.wordWrap = wordWrap }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Typewriter Scrolling", subtitle: "Keep the current line vertically centered.") {
                SettingsToggle(isOn: typewriter) { typewriter.toggle(); AppSettings.typewriter = typewriter }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Shortcuts tab

struct ShortcutsSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Shortcuts", subtitle: "Customize keyboard shortcuts. Double-click a shortcut to rebind.")

            VStack(alignment: .leading, spacing: 28) {
                ShortcutGroup(title: "General", items: [
                    ("New Note", ["⌘", "N"]),
                    ("Quick Open", ["⌘", "O"]),
                    ("Save Note", ["⌘", "S"]),
                    ("Toggle Sidebar", ["⌘", "⌥", "S"]),
                ])
                ShortcutGroup(title: "Formatting", items: [
                    ("Bold", ["⌘", "B"]),
                    ("Italic", ["⌘", "I"]),
                    ("Insert Link", ["⌘", "K"]),
                    ("Inline Code", ["⌘", "E"]),
                ])
                ShortcutGroup(title: "Navigation", items: [
                    ("Search All Notes", ["⌘", "⇧", "F"]),
                    ("Command Palette", ["⌘", "⇧", "P"]),
                    ("Toggle Preview", ["⌘", "⇧", "L"]),
                ])
            }
        }
    }
}

// MARK: - iCloud Sync tab

struct CloudSettings: View {
    @State private var syncNotes = true
    @State private var syncTags = true
    @State private var syncSettings = false
    @State private var autoDownload = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "iCloud Sync", subtitle: "Keep your notes safe and in sync across devices.")

            // Account status card
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.fromHex("#EAF1F8"))
                    Image(systemName: "icloud")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color.fromHex("#3B82C4"))
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("iCloud Drive")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Text("dylan@icloud.com")
                        .font(.system(size: 13))
                        .foregroundColor(.tertiaryText)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.fromHex("#2E9E5B")).frame(width: 7, height: 7)
                        Text("Synced")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Color.fromHex("#2E7D4F"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.fromHex("#E7F4EC")))
                    Text("Updated just now")
                        .font(.system(size: 12))
                        .foregroundColor(.tertiaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1))
            .padding(.bottom, 28)

            SettingsRow(title: "Sync Notes", subtitle: "Upload all notes to iCloud Drive.") {
                SettingsToggle(isOn: syncNotes) { syncNotes.toggle() }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Sync Tags & Folders", subtitle: "Keep your organization consistent everywhere.") {
                SettingsToggle(isOn: syncTags) { syncTags.toggle() }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Sync Settings & Shortcuts", subtitle: "Mirror app preferences across devices.") {
                SettingsToggle(isOn: syncSettings) { syncSettings.toggle() }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Auto-download New Notes", subtitle: "Download notes added on other devices automatically.") {
                SettingsToggle(isOn: autoDownload) { autoDownload.toggle() }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            // Storage usage
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Storage")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primaryText)
                        Text("Space used by notes, attachments & backups.")
                            .font(.system(size: 13))
                            .foregroundColor(.tertiaryText)
                    }
                    Spacer(minLength: 12)
                    ChipButton {} label: {
                        Text("Manage…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primaryText)
                    }
                }

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.fromHex("#D97706")).frame(width: geo.size.width * 0.38)
                        Rectangle().fill(Color.fromHex("#2D7D7D")).frame(width: geo.size.width * 0.10)
                    }
                }
                .frame(height: 9)
                .background(Capsule().fill(Color.primaryText.opacity(0.06)))
                .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        legendItem(color: Color.fromHex("#D97706"), text: "Notes — 1.9 GB")
                        legendItem(color: Color.fromHex("#2D7D7D"), text: "Attachments — 0.5 GB")
                    }
                    Text("2.4 GB of 5 GB used")
                        .font(.system(size: 13))
                        .foregroundColor(.tertiaryText)
                }
            }
            .padding(.top, 12)
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 13)).foregroundColor(.secondaryText)
        }
    }
}

// MARK: - Export tab

struct ExportSettings: View {
    @Environment(FileNoteStore.self) private var store
    @State private var format = AppSettings.exportFormat
    @State private var includeFrontmatter = AppSettings.includeFrontmatter
    @State private var preserveTags = AppSettings.preserveTags
    @State private var imageHandling = AppSettings.imageHandling

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Export", subtitle: "Choose how notes leave the app.")

            SettingsRow(title: "Default Format", subtitle: "File type used for quick exports.") {
                SettingsSegmented(
                    options: [("Markdown", "markdown"), ("PDF", "pdf"), ("HTML", "html")],
                    selection: format
                ) { format = $0; AppSettings.exportFormat = $0 }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Include YAML Frontmatter", subtitle: "Write title, date, and tags as a metadata block.") {
                SettingsToggle(isOn: includeFrontmatter) { includeFrontmatter.toggle(); AppSettings.includeFrontmatter = includeFrontmatter }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Preserve Tags", subtitle: "Keep #hashtags inline in exported text.") {
                SettingsToggle(isOn: preserveTags) { preserveTags.toggle(); AppSettings.preserveTags = preserveTags }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Image Handling", subtitle: "How embedded images are exported.") {
                SettingsSegmented(
                    options: [("Copy to Folder", "copy"), ("Link", "link")],
                    selection: imageHandling
                ) { imageHandling = $0; AppSettings.imageHandling = $0 }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            SettingsRow(title: "Export Location", subtitle: "Where exported files are saved.") {
                ChipButton {} label: {
                    HStack(spacing: 8) {
                        Text("~/Documents/Exports")
                            .font(.system(size: 14))
                            .foregroundColor(.primaryText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.tertiaryText)
                    }
                }
            }
            .padding(.vertical, 12)

            SettingsDivider()

            HStack(spacing: 10) {
                Button(action: exportAll) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Export All Notes")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accent))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {}) {
                    Text("Export Current Note")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("\(store.notes.count) note\(store.notes.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundColor(.tertiaryText)
            }
            .padding(.top, 12)
        }
    }

    /// Export every note as a Markdown file into a user-chosen directory.
    private func exportAll() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        for note in store.notes {
            let title = note.title.isEmpty ? note.filename : note.title
            let safe = title
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespaces)
            let name = (safe.isEmpty ? "Untitled" : safe) + ".md"
            let url = dir.appendingPathComponent(name)
            try? note.content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - About tab

struct AboutSettings: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "Copyright © 2025 Dylan Deng"
    }

    var body: some View {
        VStack(spacing: 28) {
            // Hero
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.fromHex("#F2A93C"), Color.fromHex("#D97706")],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundColor(.white)
                }
                .frame(width: 74, height: 74)
                .shadow(color: Color.fromHex("#D97706").opacity(0.28), radius: 9, x: 0, y: 6)

                VStack(spacing: 5) {
                    Text("Notely")
                        .font(.system(size: 25, weight: .bold))
                        .tracking(-0.4)
                        .foregroundColor(.primaryText)
                    Text("A calm, local-first Markdown editor.")
                        .font(.system(size: 14))
                        .foregroundColor(.tertiaryText)
                }

                Text("Version \(version) (\(build))")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primaryText.opacity(0.05)))
            }
            .frame(maxWidth: .infinity)

            // Links card
            VStack(spacing: 0) {
                aboutLink(icon: "sparkles", title: "What's New", trailing: "chevron.right")
                aboutDivider
                aboutLink(icon: "globe", title: "Notely Website", trailing: "arrow.up.right")
                aboutDivider
                aboutLink(icon: "heart", title: "Acknowledgements", trailing: "chevron.right")
                aboutDivider
                aboutLink(icon: "lock.shield", title: "Privacy Policy", trailing: "arrow.up.right")
            }
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1))

            // Update status
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.fromHex("#E7F4EC"))
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.fromHex("#2E9E5B"))
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("You're up to date")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primaryText)
                        Text("Last checked today at 09:14")
                            .font(.system(size: 12.5))
                            .foregroundColor(.tertiaryText)
                    }
                }
                Spacer(minLength: 12)
                ChipButton {} label: {
                    Text("Check for Updates")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primaryText)
                }
            }

            // Footer
            VStack(spacing: 3) {
                Text(copyright)
                    .font(.system(size: 12.5))
                    .foregroundColor(.tertiaryText)
                Text("Crafted with care in San Francisco.")
                    .font(.system(size: 12.5))
                    .foregroundColor(.tertiaryText.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private var aboutDivider: some View {
        Rectangle().fill(Color.primaryText.opacity(0.06)).frame(height: 1)
    }

    private func aboutLink(icon: String, title: String, trailing: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondaryText)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.primaryText)
                Spacer(minLength: 0)
                Image(systemName: trailing)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.tertiaryText.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color helper

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
