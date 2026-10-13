import Foundation
import SwiftUI

/// Centralized user defaults for app preferences.
enum AppSettings {
    static let themeKey = "notely.theme"
    static let fontSizeKey = "notely.editorFontSize"
    static let lineHeightKey = "notely.editorLineHeight"
    static let sortModeKey = "notely.sortMode"
    static let sidebarWidthKey = "notely.sidebarWidth"
    static let noteListWidthKey = "notely.noteListWidth"
    static let launchAtLoginKey = "notely.launchAtLogin"
    static let autoUpdatesKey = "notely.autoUpdates"
    static let accentColorKey = "notely.accentColor"
    static let workspacePathKey = "notely.workspacePath"
    /// Only read to migrate away from the removed theme presets.
    static let appThemeKey = "notely.appTheme"
    static let editorFontKey = "notely.editorFont"
    static let editorWidthKey = "notely.editorWidth"
    static let spellCheckKey = "notely.spellCheck"
    static let autoPairKey = "notely.autoPair"
    static let smartPunctuationKey = "notely.smartPunctuation"
    static let markdownSyntaxKey = "notely.markdownSyntax"
    static let tabSizeKey = "notely.tabSize"
    static let wordWrapKey = "notely.wordWrap"
    static let typewriterKey = "notely.typewriter"
    static let exportFormatKey = "notely.exportFormat"
    static let includeFrontmatterKey = "notely.includeFrontmatter"
    static let preserveTagsKey = "notely.preserveTags"
    static let imageHandlingKey = "notely.imageHandling"

    static var theme: String {
        get { UserDefaults.standard.string(forKey: themeKey) ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: themeKey) }
    }

    static var editorFontSize: Double {
        get { UserDefaults.standard.object(forKey: fontSizeKey) as? Double ?? 16 }
        set { UserDefaults.standard.set(newValue, forKey: fontSizeKey) }
    }

    static var editorLineHeight: Double {
        get { UserDefaults.standard.object(forKey: lineHeightKey) as? Double ?? 1.7 }
        set { UserDefaults.standard.set(newValue, forKey: lineHeightKey) }
    }

    static var sortMode: String {
        get { UserDefaults.standard.string(forKey: sortModeKey) ?? "updated-desc" }
        set { UserDefaults.standard.set(newValue, forKey: sortModeKey) }
    }

    static var sidebarWidth: Double {
        get { UserDefaults.standard.object(forKey: sidebarWidthKey) as? Double ?? 220 }
        set { UserDefaults.standard.set(newValue, forKey: sidebarWidthKey) }
    }

    static var noteListWidth: Double {
        get { UserDefaults.standard.object(forKey: noteListWidthKey) as? Double ?? 300 }
        set { UserDefaults.standard.set(newValue, forKey: noteListWidthKey) }
    }

    static var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: launchAtLoginKey) }
        set { UserDefaults.standard.set(newValue, forKey: launchAtLoginKey) }
    }

    static var autoUpdates: Bool {
        get { UserDefaults.standard.object(forKey: autoUpdatesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoUpdatesKey) }
    }


    /// The 拾页 design's blue.
    static let defaultAccentHex = "#1D6FC2"

    static var accentColorHex: String {
        get { UserDefaults.standard.string(forKey: accentColorKey) ?? defaultAccentHex }
        set { UserDefaults.standard.set(newValue, forKey: accentColorKey) }
    }

    static var workspacePath: String {
        get { UserDefaults.standard.string(forKey: workspacePathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: workspacePathKey) }
    }

    // MARK: - Appearance

    static var editorFont: String {
        get { UserDefaults.standard.string(forKey: editorFontKey) ?? "System" }
        set { UserDefaults.standard.set(newValue, forKey: editorFontKey) }
    }

    /// Editor measure: "narrow", "medium", "wide".
    static var editorWidth: String {
        get { UserDefaults.standard.string(forKey: editorWidthKey) ?? "medium" }
        set { UserDefaults.standard.set(newValue, forKey: editorWidthKey) }
    }

    // MARK: - Editor behavior

    static var spellCheck: Bool {
        get { UserDefaults.standard.object(forKey: spellCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: spellCheckKey) }
    }

    static var autoPair: Bool {
        get { UserDefaults.standard.object(forKey: autoPairKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoPairKey) }
    }

    static var smartPunctuation: Bool {
        get { UserDefaults.standard.object(forKey: smartPunctuationKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: smartPunctuationKey) }
    }

    /// When to reveal raw Markdown markers: "always", "focus", "hidden".
    static var markdownSyntax: String {
        get { UserDefaults.standard.string(forKey: markdownSyntaxKey) ?? "focus" }
        set { UserDefaults.standard.set(newValue, forKey: markdownSyntaxKey) }
    }

    static var tabSize: Int {
        get { UserDefaults.standard.object(forKey: tabSizeKey) as? Int ?? 4 }
        set { UserDefaults.standard.set(newValue, forKey: tabSizeKey) }
    }

    static var wordWrap: Bool {
        get { UserDefaults.standard.object(forKey: wordWrapKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: wordWrapKey) }
    }

    static var typewriter: Bool {
        get { UserDefaults.standard.object(forKey: typewriterKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: typewriterKey) }
    }

    // MARK: - Export

    /// Default export format: "markdown", "pdf", "html".
    static var exportFormat: String {
        get { UserDefaults.standard.string(forKey: exportFormatKey) ?? "markdown" }
        set { UserDefaults.standard.set(newValue, forKey: exportFormatKey) }
    }

    static var includeFrontmatter: Bool {
        get { UserDefaults.standard.object(forKey: includeFrontmatterKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: includeFrontmatterKey) }
    }

    static var preserveTags: Bool {
        get { UserDefaults.standard.object(forKey: preserveTagsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: preserveTagsKey) }
    }

    /// How images are exported: "copy", "link".
    static var imageHandling: String {
        get { UserDefaults.standard.string(forKey: imageHandlingKey) ?? "copy" }
        set { UserDefaults.standard.set(newValue, forKey: imageHandlingKey) }
    }
}

/// Line-spacing presets mapped to the editor line-height multiplier.
enum LineSpacingPreset: String, CaseIterable {
    case compact, cozy, relaxed

    var multiplier: Double {
        switch self {
        case .compact: return 1.4
        case .cozy: return 1.7
        case .relaxed: return 2.0
        }
    }

    var label: String { rawValue.capitalized }

    /// Resolve the preset closest to a stored multiplier.
    static func from(multiplier: Double) -> LineSpacingPreset {
        allCases.min(by: { abs($0.multiplier - multiplier) < abs($1.multiplier - multiplier) }) ?? .cozy
    }
}

/// Sort modes for the note list.
enum SortMode: String, CaseIterable {
    case updatedDesc = "updated-desc"
    case createdDesc = "created-desc"
    case titleAsc = "title-asc"

    var label: String {
        switch self {
        case .updatedDesc: return "Date Modified"
        case .createdDesc: return "Date Created"
        case .titleAsc: return "Title"
        }
    }
}

/// Theme preferences.
enum ThemePreference: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}
