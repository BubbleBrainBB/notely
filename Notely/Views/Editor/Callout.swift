import AppKit

extension NSAttributedString.Key {
    /// Marks a range as a callout block: a `:::` admonition, or a blockquote
    /// that opens with an emoji. The value is the raw type string (e.g. "note").
    /// `CodeBlockLayoutManager` draws a tinted rounded box behind such ranges,
    /// colored by `CalloutKind`.
    static let calloutType = NSAttributedString.Key("notely.calloutType")
}

/// The kind of callout, which determines its tint and icon. Unknown / missing
/// types fall back to `.note`.
enum CalloutKind {
    case note, tip, info, warning, danger

    /// Raw type used for a blockquote that starts with an emoji (`> ⚠️ …`):
    /// drawn as a gray `.info` box with the emoji standing in for the icon.
    static let emojiQuote = "quote"

    init(_ raw: String) {
        switch raw.lowercased() {
        case "tip", "hint", "success": self = .tip
        case "info", Self.emojiQuote: self = .info
        case "warning", "caution", "attention": self = .warning
        case "danger", "error", "important", "bug": self = .danger
        default: self = .note
        }
    }

    /// Title and icon color.
    var color: NSColor {
        switch self {
        case .note:    return MarkdownPalette.hex(0x2A6FB8)
        case .tip:     return MarkdownPalette.hex(0x448361)
        case .info:    return MarkdownPalette.hex(0x55534E)
        case .warning: return MarkdownPalette.hex(0x9A6B12)
        case .danger:  return MarkdownPalette.hex(0xC4402F)
        }
    }

    /// Box fill.
    var background: NSColor {
        switch self {
        case .note:    return MarkdownPalette.hex(0xE8F1FB)
        case .tip:     return MarkdownPalette.hex(0xE7F5EC)
        case .info:    return MarkdownPalette.hex(0xF1F1EF)
        case .warning: return MarkdownPalette.hex(0xFBF3DB)
        case .danger:  return MarkdownPalette.hex(0xFDECEE)
        }
    }

    var symbolName: String {
        switch self {
        case .note:    return "info.circle"
        case .tip:     return "lightbulb"
        case .info:    return "text.bubble"
        case .warning: return "exclamationmark.triangle"
        case .danger:  return "xmark.octagon"
        }
    }
}
