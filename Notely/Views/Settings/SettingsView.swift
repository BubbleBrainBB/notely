import AppKit
import ServiceManagement
import SwiftUI

// Settings as a card over the main window (design board ㉑, option B): left
// the four categories, right the selected page. Every row here changes
// something real — Export lives in the File menu and About in the app menu.

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
        case .appearance: return "textformat"
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

    static let size = CGSize(width: 700, height: 540)

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        HStack(spacing: 0) {
            navigation
            Rectangle().fill(Color.borderColor).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(state.selectedTab.title)
                        .font(.notely(17, weight: .bold))
                        .foregroundColor(.primaryText)
                    page
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay(alignment: .topTrailing) {
            SettingsCloseButton { appModel.showSettings = false }
                .padding(12)
        }
        .background(Color.fromHex("#FBFBFA"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.controlBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
        .background(
            // esc closes the card whichever control has focus.
            Button("Close Settings") { appModel.showSettings = false }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        )
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.notely(15, weight: .bold))
                .foregroundColor(.primaryText)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            ForEach(SettingsTab.allCases) { tab in
                SettingsNavItem(tab: tab, isSelected: state.selectedTab == tab) {
                    state.selectedTab = tab
                }
            }
            Spacer(minLength: 0)
            Text("Notely \(version) · esc to close")
                .font(.notely(11))
                .foregroundColor(.faintText)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(width: 190, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Color.sidebarBg)
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

/// × at the card's top-right corner; esc and a click outside also close.
private struct SettingsCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovering ? .primaryText : .tertiaryText)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isHovering ? Color.cardHover : Color.clear))
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
            HStack(spacing: 9) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .primaryText : .tertiaryText)
                    .frame(width: 16)
                Text(tab.title)
                    .font(.notely(13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primaryText : .secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.selectedBg : (isHovering ? Color.cardHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Building blocks

/// A titled group of rows on a white card.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.notely(13, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .padding(.leading, 2)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.controlBorder, lineWidth: 1)
            )
        }
    }
}

/// One setting: label (and an optional note under it) left, control right.
struct SettingsItem<Control: View>: View {
    let title: String
    var detail: String? = nil
    var isLast = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 16) {
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
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.borderColor).frame(height: 1)
            }
        }
    }
}

/// A segmented control in the card style: white pill on a light track. The
/// native one fills the selection with the accent, which reads as an alert
/// next to the accent swatches.
struct SettingsSegmented<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Text(option.label)
                    .font(.notely(12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .primaryText : .secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isSelected ? Color.surface : Color.clear)
                            .shadow(color: .black.opacity(isSelected ? 0.14 : 0), radius: 1, y: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option.value }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.fromHex("#EDEDEB")))
        .fixedSize()
    }
}

/// A small white button, matching the font picker.
struct SettingsButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.notely(12.5))
                .foregroundColor(.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color.fromHex("#FBFBFA") : Color.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.controlBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 0.5, y: 0.5)
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
        SettingsGroup {
            SettingsItem(title: "Notes Folder", detail: folderPath) {
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
            SettingsItem(title: "Open at Login", detail: loginItemError, isLast: true) {
                Toggle("", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
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
        ("Ink", "#37352F"),
        ("Green", "#448361"),
        ("Purple", "#9065B0"),
        ("Red", "#C4402F"),
    ]

    private var lineSpacing: Binding<LineSpacingPreset> {
        Binding(get: { LineSpacingPreset.from(multiplier: lineHeight) },
                set: { lineHeight = $0.multiplier })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview

            SettingsGroup {
                SettingsItem(title: "Accent Color", detail: "Selections, links and switches.", isLast: true) {
                    HStack(spacing: 10) {
                        ForEach(accentColors, id: \.hex) { color in
                            AccentDot(hex: color.hex, isSelected: themeManager.accentHex == color.hex) {
                                themeManager.setAccent(color.hex)
                            }
                            .help(color.name)
                        }
                    }
                }
            }

            SettingsGroup(title: "Text") {
                SettingsItem(title: "Font", detail: "Body text of every note.") {
                    FontPicker(selection: editorFont) { editorFont = $0 }
                }
                SettingsItem(title: "Size") {
                    Stepper(value: $fontSize, in: 12...24, step: 1) {
                        Text("\(Int(fontSize)) pt")
                            .font(.notely(12.5))
                            .foregroundColor(.primaryText)
                            .monospacedDigit()
                    }
                    .controlSize(.small)
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

    /// The body text as the editor will set it, so a change shows at once.
    private var preview: some View {
        let font = WysiwygEngine.resolveFont(name: editorFont, size: CGFloat(fontSize))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.notely(11, weight: .semibold))
                .foregroundColor(.faintText)
            Text("阿里云栖这个新模型有点猛，Qwen Image 2.1 做的非常完美。\nThe quick brown fox jumps over the lazy dog.")
                .font(Font(font))
                .lineSpacing(CGFloat(fontSize) * CGFloat(lineHeight - 1))
                .foregroundColor(.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.controlBorder, lineWidth: 1)
        )
    }
}

private struct AccentDot: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.fromHex(hex))
                .frame(width: 16, height: 16)
                .padding(2.5)
                .overlay(Circle().strokeBorder(isSelected ? Color.fromHex(hex) : .clear, lineWidth: 1.5))
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
            .padding(.trailing, 7)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.controlBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 0.5, y: 0.5)
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
        SettingsGroup {
            SettingsItem(title: "Check Spelling", detail: "Underline misspelled words as you type.") {
                Toggle("", isOn: $spellCheck)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            SettingsItem(title: "Smart Quotes and Dashes", detail: "Turn \"quotes\" into “quotes” and -- into —.",
                         isLast: true) {
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
        ("Formatting", [
            ("Bold", "⌘B"),
            ("Italic", "⌘I"),
            ("Insert Link", "⌘K"),
            ("Toggle To-do", "⇧⌘T"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \.title) { group in
                SettingsGroup(title: group.title) {
                    ForEach(Array(group.items.enumerated()), id: \.offset) { index, item in
                        SettingsItem(title: item.name, isLast: index == group.items.count - 1) {
                            Text(item.keys)
                                .font(.notely(12.5))
                                .foregroundColor(.secondaryText)
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
