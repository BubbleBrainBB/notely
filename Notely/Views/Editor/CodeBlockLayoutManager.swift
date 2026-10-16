import AppKit
import SwiftUI

/// Editor colors from the 拾页 Markdown spec (design canvas board ⑩).
enum MarkdownPalette {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1)
    }

    static let primary = hex(0x37352F)
    /// Bold text when the accent is too close to the body ink to tell apart
    /// (the Ink accent): a step darker, so **strong** still reads at a glance.
    static let strong = hex(0x111110)

    /// Bold text in the user's accent color; the deeper ink for the Ink accent.
    static func strong(accentHex: String) -> NSColor {
        let digits = accentHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt32(digits, radix: 16), value != 0x37352F else { return strong }
        return hex(value)
    }
    static let secondary = hex(0x55534E)
    static let tertiary = hex(0x73726E)
    static let faint = hex(0x9B9A97)
    /// Markdown syntax revealed on the caret's paragraph.
    static let marker = hex(0xC7C6C2)
    static let rule = hex(0xEDEDEB)
    static let codeBlockBg = hex(0xF7F7F5)
    static let inlineBg = hex(0xF1F1EF)
    static let inlineCode = hex(0xC4402F)
    static let linkUnderline = hex(0xD3D3CF)
    static let highlight = hex(0xFBF3DB)
    static let tableBorder = hex(0xE9E9E7)
    static let checkboxBorder = hex(0xB4B3AF)
    static let nestedQuoteBar = hex(0xD3D3CF)

    static let syntaxKeyword = hex(0x9065B0)
    static let syntaxString = hex(0x448361)
    static let syntaxNumber = hex(0x9A6B12)

    /// The user's accent (Settings › Appearance), for checked to-dos.
    static var accent: NSColor { NSColor(Color.accent) }
}

extension NSAttributedString.Key {
    /// Marks a range as belonging to a fenced code block. `CodeBlockLayoutManager`
    /// paints a single rounded rectangle behind each such range. Set instead of
    /// `.backgroundColor`, which TextKit paints per-glyph-run (ragged width, no
    /// padding, no corners) rather than as one uniform box.
    static let codeBlockBackground = NSAttributedString.Key("notely.codeBlockBackground")
    /// The fenced block's language (its info string), drawn top-right in the box.
    static let codeBlockLanguage = NSAttributedString.Key("notely.codeBlockLanguage")

    /// Marks the hidden prefix of a list item. The value is a `ListMarker`
    /// describing the bullet, number or checkbox to draw in the indent.
    static let listMarker = NSAttributedString.Key("notely.listMarker")

    /// Blockquote nesting depth (Int) on each quote line; bars are drawn in the
    /// indent, one per level.
    static let blockquoteDepth = NSAttributedString.Key("notely.blockquoteDepth")

    /// A rounded fill behind an inline span (inline code, hashtags). The value
    /// is the fill `NSColor`.
    static let inlinePill = NSAttributedString.Key("notely.inlinePill")

    /// A text highlight (`==text==`): a fill hugging the glyphs, without the
    /// padding of `.inlinePill`. The value is the fill `NSColor`.
    static let textHighlight = NSAttributedString.Key("notely.textHighlight")

    /// A horizontal rule line, drawn across the column.
    static let horizontalRule = NSAttributedString.Key("notely.horizontalRule")

    /// On a callout's first character: the `CalloutKind` raw type whose icon is
    /// drawn in the callout's top-left corner.
    static let calloutIcon = NSAttributedString.Key("notely.calloutIcon")
}

/// What to draw in a list item's indent.
final class ListMarker: NSObject {
    enum Kind: Equatable {
        case bullet(level: Int)
        case ordered(label: String)
        case task(checked: Bool)
    }

    let kind: Kind
    /// The paragraph's head indent; the marker sits in the 24pt slot before it.
    let indent: CGFloat
    let font: NSFont

    init(kind: Kind, indent: CGFloat, font: NSFont) {
        self.kind = kind
        self.indent = indent
        self.font = font
    }

    static let slotWidth: CGFloat = 24

    /// The checkbox's frame relative to the container's left edge and the
    /// line's baseline, shared by drawing and click hit-testing.
    func checkboxRect(baselineY: CGFloat) -> NSRect {
        let size: CGFloat = 16
        let centerY = baselineY - font.capHeight / 2
        return NSRect(x: indent - Self.slotWidth + 1, y: centerY - size / 2, width: size, height: size)
    }
}

/// Layout manager that draws the editor's non-text decorations: block boxes
/// (code, callouts), quote bars, list bullets / numbers / checkboxes, inline
/// pills, rules and callout icons. The Markdown
/// syntax these stand in for is collapsed to zero width by `WysiwygEngine`.
final class CodeBlockLayoutManager: NSLayoutManager {
    /// Extra height added above and below a block box's text.
    var verticalPadding: CGFloat = 10
    var cornerRadius: CGFloat = 8

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawCodeBlockBoxes(forGlyphRange: glyphsToShow, at: origin)
        drawCalloutBoxes(forGlyphRange: glyphsToShow, at: origin)
        drawInlineFills(.inlinePill, padding: WysiwygEngine.pillPadding, radius: 4,
                        forGlyphRange: glyphsToShow, at: origin)
        drawInlineFills(.textHighlight, padding: 0, radius: 3,
                        forGlyphRange: glyphsToShow, at: origin)
        // Draw text backgrounds (highlight, selection) on top of the boxes so
        // selection inside a block stays visible.
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawQuoteBars(forGlyphRange: glyphsToShow, at: origin)
        drawListMarkers(forGlyphRange: glyphsToShow, at: origin)
        drawRules(forGlyphRange: glyphsToShow, at: origin)
        drawCalloutIcons(forGlyphRange: glyphsToShow, at: origin)
        drawCodeLanguages(forGlyphRange: glyphsToShow, at: origin)
    }

    // MARK: - Geometry helpers

    /// Baseline of the line holding `glyphIndex`, in view coordinates.
    private func baselineY(forGlyphAt glyphIndex: Int, origin: NSPoint) -> CGFloat {
        let fragRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return origin.y + fragRect.minY + location(forGlyphAt: glyphIndex).y
    }

    /// Enumerates runs of `key` intersecting the glyphs being drawn.
    private func enumerate(_ key: NSAttributedString.Key, in glyphsToShow: NSRange,
                           _ body: (Any, NSRange, NSRange) -> Void) {
        guard let storage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(key, in: charRange, options: []) { value, range, _ in
            guard let value else { return }
            let gRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard gRange.length > 0 else { return }
            body(value, range, gRange)
        }
    }

    /// The bottom of a run's last line, minus that line's trailing line
    /// spacing, so a bar or box ends at the text rather than in the gap below.
    private func textBottom(ofCharacterRange range: NSRange, glyphRange gRange: NSRange) -> CGFloat {
        let lastGlyph = NSMaxRange(gRange) - 1
        let frag = lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
        let lastChar = max(range.location, NSMaxRange(range) - 1)
        let spacing = (textStorage?.attribute(.paragraphStyle, at: lastChar, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0
        return frag.maxY - spacing
    }

    // MARK: - Blocks

    private func drawCodeBlockBoxes(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        enumerateBlockBoxes(.codeBlockBackground, forGlyphRange: glyphsToShow, at: origin) { rect, value, _ in
            guard (value as? Bool) == true else { return }
            MarkdownPalette.codeBlockBg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: self.cornerRadius, yRadius: self.cornerRadius).fill()
        }
    }

    private func drawCalloutBoxes(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        enumerateBlockBoxes(.calloutType, forGlyphRange: glyphsToShow, at: origin) { rect, value, _ in
            guard let raw = value as? String else { return }
            CalloutKind(raw).background.setFill()
            NSBezierPath(roundedRect: rect, xRadius: self.cornerRadius, yRadius: self.cornerRadius).fill()
        }
    }

    private func drawCodeLanguages(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        enumerateBlockBoxes(.codeBlockBackground, forGlyphRange: glyphsToShow, at: origin) { rect, _, range in
            guard let language = self.textStorage?.attribute(.codeBlockLanguage, at: range.location, effectiveRange: nil) as? String,
                  !language.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: MarkdownPalette.tertiary,
            ]
            let size = (language as NSString).size(withAttributes: attrs)
            (language as NSString).draw(at: NSPoint(x: rect.maxX - 12 - size.width, y: rect.minY + 7), withAttributes: attrs)
        }
    }

    private func drawCalloutIcons(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        enumerate(.calloutIcon, in: glyphsToShow) { value, _, gRange in
            guard let raw = value as? String else { return }
            let kind = CalloutKind(raw)
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [kind.color]))
            guard let image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return }
            // The tagged character is the collapsed `:::`, so center on the
            // title font's cap height rather than that character's font.
            let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            let baseline = self.baselineY(forGlyphAt: gRange.location, origin: origin)
            let centerY = baseline - font.capHeight / 2
            let size = image.size
            image.draw(in: NSRect(x: origin.x + 14 + (16 - size.width) / 2, y: centerY - size.height / 2,
                                  width: size.width, height: size.height))
        }
    }

    /// Shared geometry for block backgrounds. Enumerates the WHOLE storage (not
    /// just `glyphsToShow`) so a partial redraw still paints each block's box at
    /// its full size; skips boxes outside the dirty region. Calls `draw` with the
    /// box rect (full column width, vertical padding applied) in view
    /// coordinates, the attribute value and the run's character range.
    private func enumerateBlockBoxes(_ key: NSAttributedString.Key,
                                     forGlyphRange glyphsToShow: NSRange,
                                     at origin: NSPoint,
                                     draw: (NSRect, Any, NSRange) -> Void) {
        guard let storage = textStorage, let container = textContainers.first else { return }
        let dirtyRect = boundingRect(forGlyphRange: glyphsToShow, in: container)
            .offsetBy(dx: origin.x, dy: origin.y)
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.enumerateAttribute(key, in: fullRange, options: []) { value, range, _ in
            guard let value else { return }
            let blockGlyphRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard blockGlyphRange.length > 0 else { return }
            var rect = boundingRect(forGlyphRange: blockGlyphRange, in: container)
            rect.size.height = textBottom(ofCharacterRange: range, glyphRange: blockGlyphRange) - rect.minY
            rect.origin.x = 0
            rect.size.width = container.size.width
            rect = rect.insetBy(dx: 0, dy: -verticalPadding)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            guard rect.intersects(dirtyRect) else { return }
            draw(rect, value, range)
        }
    }

    // MARK: - Quotes

    private func drawQuoteBars(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        enumerate(.blockquoteDepth, in: glyphsToShow) { value, range, gRange in
            guard let depth = value as? Int, depth > 0 else { return }
            let top = origin.y + lineFragmentRect(forGlyphAt: gRange.location, effectiveRange: nil).minY
            let bottom = origin.y + textBottom(ofCharacterRange: range, glyphRange: gRange)
            for level in 1...depth {
                let x = origin.x + CGFloat(level - 1) * WysiwygEngine.quoteIndent
                (level == 1 ? MarkdownPalette.primary : MarkdownPalette.nestedQuoteBar).setFill()
                NSRect(x: x, y: top + 2, width: 3, height: max(0, bottom - top - 2)).fill()
            }
        }
    }

    // MARK: - Lists

    private func drawListMarkers(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        enumerate(.listMarker, in: glyphsToShow) { value, _, gRange in
            guard let marker = value as? ListMarker else { return }
            let baseline = baselineY(forGlyphAt: gRange.location, origin: origin)
            let centerY = baseline - marker.font.capHeight / 2
            let slotLeft = origin.x + marker.indent - ListMarker.slotWidth

            switch marker.kind {
            case .bullet(let level):
                let centerX = slotLeft + 7
                MarkdownPalette.primary.set()
                switch level % 3 {
                case 0:
                    let d = max(5, (marker.font.pointSize * 0.33).rounded())
                    NSBezierPath(ovalIn: NSRect(x: centerX - d / 2, y: centerY - d / 2, width: d, height: d)).fill()
                case 1:
                    let d = max(5, (marker.font.pointSize * 0.33).rounded())
                    let ring = NSBezierPath(ovalIn: NSRect(x: centerX - d / 2 + 0.6, y: centerY - d / 2 + 0.6, width: d - 1.2, height: d - 1.2))
                    ring.lineWidth = 1.2
                    ring.stroke()
                default:
                    let s = max(4, (marker.font.pointSize * 0.28).rounded())
                    NSRect(x: centerX - s / 2, y: centerY - s / 2, width: s, height: s).fill()
                }

            case .ordered(let label):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: marker.font.pointSize, weight: .regular),
                    .foregroundColor: MarkdownPalette.primary,
                ]
                let size = (label as NSString).size(withAttributes: attrs)
                let font = attrs[.font] as! NSFont
                (label as NSString).draw(at: NSPoint(x: origin.x + marker.indent - 6 - size.width,
                                                     y: baseline - font.ascender),
                                         withAttributes: attrs)

            case .task(let checked):
                var box = marker.checkboxRect(baselineY: baseline)
                box.origin.x += origin.x
                if checked {
                    MarkdownPalette.accent.setFill()
                    NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: box.minX + 4, y: box.midY + 0.5))
                    check.line(to: NSPoint(x: box.minX + 7, y: box.midY + 3.5))
                    check.line(to: NSPoint(x: box.maxX - 3.5, y: box.minY + 4.5))
                    check.lineWidth = 2
                    check.lineCapStyle = .round
                    check.lineJoinStyle = .round
                    NSColor.white.setStroke()
                    check.stroke()
                } else {
                    let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
                    path.lineWidth = 1.5
                    MarkdownPalette.checkboxBorder.setStroke()
                    path.stroke()
                }
            }
        }
    }

    // MARK: - Inline pills

    /// Rounded fills behind inline spans, sized to the glyphs (ascender to
    /// descender) rather than the whole line fragment, which includes the
    /// line spacing below the text.
    private func drawInlineFills(_ key: NSAttributedString.Key, padding: CGFloat, radius: CGFloat,
                                 forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, let container = textContainers.first else { return }
        enumerate(key, in: glyphsToShow) { value, range, gRange in
            guard let color = value as? NSColor else { return }
            let font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
                ?? NSFont.systemFont(ofSize: 14)
            // One pill per line the span wraps across.
            enumerateLineFragments(forGlyphRange: gRange) { _, _, _, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, gRange)
                guard part.length > 0 else { return }
                let bounds = self.boundingRect(forGlyphRange: part, in: container)
                let baseline = self.baselineY(forGlyphAt: part.location, origin: origin)
                let inset: CGFloat = padding > 0 ? 2 : 1
                let pill = NSRect(x: origin.x + bounds.minX - padding,
                                  y: baseline - font.ascender - inset,
                                  width: bounds.width + padding,
                                  height: font.ascender - font.descender + inset * 2)
                color.setFill()
                NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            }
        }
    }

    // MARK: - Rules

    private func drawRules(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let container = textContainers.first else { return }
        enumerate(.horizontalRule, in: glyphsToShow) { _, range, gRange in
            let frag = lineFragmentRect(forGlyphAt: gRange.location, effectiveRange: nil)
            let bottom = textBottom(ofCharacterRange: range, glyphRange: gRange)
            let y = origin.y + ((frag.minY + bottom) / 2).rounded()
            MarkdownPalette.rule.setFill()
            NSRect(x: origin.x, y: y, width: container.size.width, height: 1).fill()
        }
    }
}
