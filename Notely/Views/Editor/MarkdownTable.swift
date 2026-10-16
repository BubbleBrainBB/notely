import AppKit

/// An attachment whose visual representation stands in for a span of raw
/// Markdown. `markdownSource` is the exact text it replaces, so the document's
/// raw Markdown can always be reconstructed (see `WysiwygTextView.markdownString`).
protocol MarkdownBackedAttachment: AnyObject {
    var markdownSource: String { get }
}

/// Parsed structure of a GFM-style Markdown table.
struct MarkdownTable: Equatable {
    enum Alignment: Equatable { case left, center, right }
    var headers: [String]
    var alignments: [Alignment]
    var rows: [[String]]
    var columnCount: Int { headers.count }
}

/// One table found in a document: its raw character range plus the parsed table.
struct ParsedMarkdownTable {
    let range: NSRange
    let table: MarkdownTable
}

/// Detects GFM pipe tables in raw Markdown. A table is a row containing `|`
/// immediately followed by a delimiter row (`| --- | :--: |`), then zero or more
/// rows. Tables inside fenced code blocks are ignored.
enum MarkdownTableParser {

    static func tables(in text: NSString) -> [ParsedMarkdownTable] {
        var lines: [(range: NSRange, text: String)] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines]) { sub, range, _, _ in
            lines.append((range, sub ?? ""))
        }

        // Mark which line indices are inside a fenced code block.
        var inFence = [Bool](repeating: false, count: lines.count)
        var fenced = false
        for (i, line) in lines.enumerated() {
            let t = line.text.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                inFence[i] = true   // the fence line itself is "in" a block
                fenced.toggle()
                continue
            }
            inFence[i] = fenced
        }

        var results: [ParsedMarkdownTable] = []
        var i = 0
        while i < lines.count {
            guard !inFence[i] else { i += 1; continue }
            let header = lines[i].text
            if isTableRow(header), i + 1 < lines.count, !inFence[i + 1],
               isDelimiterRow(lines[i + 1].text),
               lines[i + 1].text.contains("|") || splitCells(header).count == 1 {
                var j = i + 2
                while j < lines.count, !inFence[j], isTableRow(lines[j].text) { j += 1 }
                let start = lines[i].range.location
                let lastLine = lines[j - 1].range
                let blockRange = NSRange(location: start, length: (lastLine.location + lastLine.length) - start)
                if let table = parse(header: header,
                                     delimiter: lines[i + 1].text,
                                     body: (i + 2..<j).map { lines[$0].text }) {
                    results.append(ParsedMarkdownTable(range: blockRange, table: table))
                }
                i = j
            } else {
                i += 1
            }
        }
        return results
    }

    static func isTableRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("|") else { return false }
        if t.hasPrefix("```") || t.hasPrefix("~~~") { return false }
        return true
    }

    static func isDelimiterRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        return t.range(of: #"^\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?$"#, options: .regularExpression) != nil
    }

    static func splitCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func parse(header: String, delimiter: String, body: [String]) -> MarkdownTable? {
        let headers = splitCells(header)
        guard !headers.isEmpty else { return nil }
        var alignments = splitCells(delimiter).map { cell -> MarkdownTable.Alignment in
            let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
            if left && right { return .center }
            if right { return .right }
            return .left
        }
        while alignments.count < headers.count { alignments.append(.left) }
        if alignments.count > headers.count { alignments = Array(alignments.prefix(headers.count)) }

        let rows = body.map { line -> [String] in
            var cells = splitCells(line)
            while cells.count < headers.count { cells.append("") }
            if cells.count > headers.count { cells = Array(cells.prefix(headers.count)) }
            return cells
        }
        return MarkdownTable(headers: headers, alignments: alignments, rows: rows)
    }
}

/// A non-editable text attachment that draws a Markdown table as a bordered
/// grid. Double-clicking it (see `WysiwygTextView`) reveals the raw Markdown for
/// editing; `markdownSource` lets the raw document be reconstructed.
final class TableAttachment: NSTextAttachment, MarkdownBackedAttachment {
    let markdownSource: String

    init(table: MarkdownTable, markdownSource: String, font: NSFont, maxWidth: CGFloat) {
        self.markdownSource = markdownSource
        super.init(data: nil, ofType: nil)
        let rendered = TableAttachment.render(table: table, font: font, maxWidth: maxWidth)
        image = rendered
        bounds = NSRect(origin: .zero, size: rendered.size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func render(table: MarkdownTable, font baseFont: NSFont, maxWidth: CGFloat) -> NSImage {
        let cols = max(1, table.columnCount)
        let headerFont = NSFont.systemFont(ofSize: baseFont.pointSize - 0.5, weight: .semibold)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        let border: CGFloat = 1
        let padH: CGFloat = 12
        let padV: CGFloat = 8
        let radius: CGFloat = 8

        let borderColor = MarkdownPalette.tableBorder
        let headerBg = MarkdownPalette.codeBlockBg

        let allRows: [[String]] = [table.headers] + table.rows
        func cell(_ r: Int, _ c: Int) -> String { c < allRows[r].count ? allRows[r][c] : "" }

        // Left-aligned columns (the parser's default for a plain `---`) whose
        // body cells are all numbers read better right-aligned, tabular digits.
        func isNumeric(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
            return !t.isEmpty && Double(t.trimmingCharacters(in: CharacterSet(charactersIn: "%$¥€+-"))) != nil
        }
        let numericColumn: [Bool] = (0..<cols).map { c in
            !table.rows.isEmpty && table.rows.allSatisfy { isNumeric(c < $0.count ? $0[c] : "") }
        }
        func alignment(_ c: Int) -> NSTextAlignment {
            if table.alignments.indices.contains(c) {
                switch table.alignments[c] {
                case .center: return .center
                case .right: return .right
                case .left: break
                }
            }
            return numericColumn[c] ? .right : .left
        }
        func font(_ r: Int, _ c: Int) -> NSFont { r == 0 ? headerFont : (numericColumn[c] ? numberFont : baseFont) }
        func color(forRow r: Int) -> NSColor { r == 0 ? MarkdownPalette.secondary : MarkdownPalette.primary }
        func textWidth(_ s: String, _ f: NSFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: f]).width }

        var natural = [CGFloat](repeating: 8, count: cols)
        for r in 0..<allRows.count {
            for c in 0..<cols { natural[c] = max(natural[c], textWidth(cell(r, c), font(r, c))) }
        }
        let chrome = border * CGFloat(cols + 1) + padH * 2 * CGFloat(cols)
        let availText = max(CGFloat(cols) * 30, maxWidth - chrome)
        let totalNatural = max(1, natural.reduce(0, +))
        var colW = natural
        if totalNatural > availText {
            let scale = availText / totalNatural
            colW = natural.map { max(30, floor($0 * scale)) }
        }
        let totalWidth = ceil(colW.reduce(0, +) + chrome)
        // `colW` is each column's text width; a cell spans that plus padding.
        let cellW = colW.map { $0 + padH * 2 }

        func cellHeight(_ s: String, _ width: CGFloat, _ f: NSFont) -> CGFloat {
            let attr = NSAttributedString(string: s.isEmpty ? " " : s, attributes: [.font: f])
            let r = attr.boundingRect(with: NSSize(width: width, height: 1_000_000),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading])
            return ceil(r.height)
        }
        var rowH = [CGFloat]()
        for r in 0..<allRows.count {
            var h: CGFloat = 0
            for c in 0..<cols { h = max(h, cellHeight(cell(r, c), colW[c], font(r, c))) }
            rowH.append(h + padV * 2)
        }
        let totalHeight = ceil(rowH.reduce(0, +) + border * CGFloat(allRows.count + 1))
        let size = NSSize(width: max(totalWidth, 1), height: max(totalHeight, 1))

        return NSImage(size: size, flipped: true) { _ in
            let outline = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: border / 2, dy: border / 2),
                                       xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()

            // Header background.
            headerBg.setFill()
            NSRect(x: 0, y: 0, width: size.width, height: rowH[0] + border).fill()

            // Inner grid lines (the rounded outline is stroked separately).
            borderColor.setFill()
            var yc: CGFloat = 0
            for r in 0..<(allRows.count - 1) {
                yc += rowH[r] + border
                NSRect(x: 0, y: yc, width: size.width, height: border).fill()
            }
            var xc: CGFloat = 0
            for c in 0..<(cols - 1) {
                xc += cellW[c] + border
                NSRect(x: xc, y: 0, width: border, height: size.height).fill()
            }
            NSGraphicsContext.restoreGraphicsState()

            outline.lineWidth = border
            borderColor.setStroke()
            outline.stroke()

            // Cell text.
            var rowY: CGFloat = border
            for r in 0..<allRows.count {
                var colX: CGFloat = border
                for c in 0..<cols {
                    let para = NSMutableParagraphStyle()
                    para.alignment = alignment(c)
                    para.lineBreakMode = .byWordWrapping
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font(r, c), .foregroundColor: color(forRow: r), .paragraphStyle: para,
                    ]
                    let rect = NSRect(x: colX + padH, y: rowY + padV,
                                      width: max(1, colW[c]), height: rowH[r] - padV * 2)
                    (cell(r, c) as NSString).draw(in: rect, withAttributes: attrs)
                    colX += cellW[c] + border
                }
                rowY += rowH[r] + border
            }
            return true
        }
    }
}
