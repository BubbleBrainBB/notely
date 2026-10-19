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
        case .note:    return MarkdownPalette.adaptive(0x2A6FB8, 0x6FA8E6)
        case .tip:     return MarkdownPalette.adaptive(0x448361, 0x6FB08A)
        case .info:    return MarkdownPalette.adaptive(0x55534E, 0xC3C0B9)
        case .warning: return MarkdownPalette.adaptive(0x9A6B12, 0xD1A04A)
        case .danger:  return MarkdownPalette.adaptive(0xC4402F, 0xE5735F)
        }
    }

    /// Box fill.
    var background: NSColor {
        switch self {
        case .note:    return MarkdownPalette.adaptive(0xE8F1FB, 0x1E2A38)
        case .tip:     return MarkdownPalette.adaptive(0xE7F5EC, 0x1E2E25)
        case .info:    return MarkdownPalette.adaptive(0xF1F1EF, 0x2E2D2A)
        case .warning: return MarkdownPalette.adaptive(0xFBF3DB, 0x3A3220)
        case .danger:  return MarkdownPalette.adaptive(0xFDECEE, 0x3A2224)
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
