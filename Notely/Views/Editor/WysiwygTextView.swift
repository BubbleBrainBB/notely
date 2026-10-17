import AppKit
import AVKit
import SwiftUI

/// Simple file-based diagnostics.
enum Diag {
    private static let enabled = false

    private static let path: String = {
        let home = NSHomeDirectory()
        return "\(home)/notely_debug.log"
    }()

    static func log(_ message: String) {
        guard enabled else { return }
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        // Also print to stderr for immediate feedback
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                if let handle = FileHandle(forWritingAtPath: path) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }
}

extension Notification.Name {
    static let imageDidLoad = Notification.Name("notely.imageDidLoad")
    static let animatedImageFrameDidChange = Notification.Name("notely.animatedImageFrameDidChange")
    /// Posted by the outline rail; userInfo["index"] = ordinal of the heading to
    /// scroll to (0-based, in document order).
    static let scrollToHeading = Notification.Name("notely.scrollToHeading")
}

/// Custom scroll view that ensures mouse clicks properly activate the text
/// view as first responder, even inside SwiftUI's NavigationSplitView.
final class EditorScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if let textView = documentView as? NSTextView, textView.window?.firstResponder != textView {
            textView.window?.makeFirstResponder(textView)
        }
        super.mouseDown(with: event)
    }
}

/// SwiftUI wrapper for the WYSIWYG text editor.
///
/// IMPORTANT: This wrapper does NOT use a @Binding for the text content.
/// Instead, the parent passes the initial text and observes changes via a
/// closure. This breaks the feedback loop where every keystroke would
/// trigger a SwiftUI re-render that resets the NSTextView.
struct WysiwygEditor: NSViewRepresentable {
    let initialText: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let fontName: String
    let editorWidth: String
    var spellCheck = AppSettings.defaultSpellCheck
    var smartPunctuation = AppSettings.defaultSmartPunctuation
    /// A draft's faint "Title" and hint, drawn while it is still untouched.
    var draftPlaceholder: WysiwygTextView.DraftPlaceholder? = nil
    /// Take keyboard focus, caret at the end, once the editor is on screen.
    var focusesOnAppear = false
    let onTextChange: (String) -> Void

    /// Settings › Editor. Set only on change: assigning restarts the checker.
    static func applyTypingOptions(_ textView: NSTextView, spellCheck: Bool, smartPunctuation: Bool) {
        if textView.isContinuousSpellCheckingEnabled != spellCheck {
            textView.isContinuousSpellCheckingEnabled = spellCheck
        }
        if textView.isAutomaticQuoteSubstitutionEnabled != smartPunctuation {
            textView.isAutomaticQuoteSubstitutionEnabled = smartPunctuation
            textView.isAutomaticDashSubstitutionEnabled = smartPunctuation
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = EditorScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.focusRingType = .none
        scrollView.borderType = .noBorder

        let textStorage = NSTextStorage()
        let layoutManager = CodeBlockLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = WysiwygTextView(
            frame: NSRect(origin: .zero, size: NSSize(width: 1, height: scrollView.contentSize.height)),
            textContainer: textContainer
        )
        textView.fontSize = fontSize
        textView.lineHeight = lineHeight
        textView.fontName = fontName
        textView.editorWidth = editorWidth
        textView.draftPlaceholder = draftPlaceholder
        textView.focusesOnAppear = focusesOnAppear
        Self.applyTypingOptions(textView, spellCheck: spellCheck, smartPunctuation: smartPunctuation)
        textView.delegate = context.coordinator
        textView.onTextChange = { newText in
            context.coordinator.lastKnownText = newText
            context.coordinator.onTextChange(newText)
        }
        textView.string = initialText
        // Build the engine at the correct font/line-height up front so the first
        // `updateNSView` does not have to rebuild it.
        textView.rebuildEngineAndRestyle()

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastKnownText = initialText
        Diag.log("makeNSView: textView frame=\(textView.frame) isEditable=\(textView.isEditable)")
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? WysiwygTextView else { return }
        Self.applyTypingOptions(textView, spellCheck: spellCheck, smartPunctuation: smartPunctuation)
        if textView.draftPlaceholder != draftPlaceholder {
            textView.draftPlaceholder = draftPlaceholder
            textView.needsDisplay = true
        }

        // Re-bind the text-change callback to the CURRENT note's EditorView. The
        // Coordinator is created once (makeCoordinator), so without this a reused
        // editor would keep routing saves through the FIRST note's closure —
        // writing the displayed note's text into the wrong note's file.
        context.coordinator.onTextChange = onTextChange

        // Only sync text when switching notes (external content change),
        // never during typing. We detect this by comparing initialText against
        // the coordinator's lastKnownText. If they match, the change came from
        // user typing (which already updated the text view). If they differ,
        // it's an external change (note switch) that needs to be pushed in.
        if initialText != context.coordinator.lastKnownText {
            context.coordinator.lastKnownText = initialText
            let selectedRange = textView.selectedRange()
            textView.string = initialText
            textView.restyle()
            let clampedLocation = min(selectedRange.location, (initialText as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            Diag.log("updateNSView: text synced for note switch, len=\(initialText.count)")
        }

        // The scroll view fills the full width of the pane, so its vertical
        // scroller sits flush against the right edge. The readable text column is
        // centered and capped via textContainerInset rather than by shrinking the
        // scroll view (which is what pushed the scroller inward before).
        textView.editorWidth = editorWidth
        let available = max(nsView.contentSize.width, 1)
        let sideInset = textView.sideInset(forAvailableWidth: available)
        let widthChanged = abs(textView.frame.width - available) > 0.5
        let insetChanged = abs(textView.textContainerInset.width - sideInset) > 0.5
        if widthChanged || insetChanged {
            textView.setFrameSize(NSSize(width: available, height: max(textView.frame.height, nsView.contentSize.height)))
            textView.textContainerInset = NSSize(width: sideInset, height: textView.textContainerInset.height)
            textView.textContainer?.containerSize = NSSize(width: max(1, available - sideInset * 2), height: CGFloat.greatestFiniteMagnitude)
        }

        textView.fontSize = fontSize
        textView.lineHeight = lineHeight
        textView.fontName = fontName
        // Keep the caret colored by the live theme accent (it can change at
        // runtime via Settings without the text view being recreated).
        textView.insertionPointColor = NSColor(Color.accent)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(Color.accent).withAlphaComponent(0.18)]
        textView.rebuildEngineAndRestyleIfNeeded()
        textView.fitFrameToContent()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange: (String) -> Void
        weak var textView: NSTextView?
        var lastKnownText: String = ""

        init(onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
        }
    }
}

/// The WYSIWYG-capable NSTextView subclass.
final class WysiwygTextView: NSTextView {
    var fontSize: CGFloat = 16
    var lineHeight: CGFloat = 1.75
    var fontName: String = "System"
    var onTextChange: ((String) -> Void)?
    var draftPlaceholder: DraftPlaceholder?
    var focusesOnAppear = false
    private var engine: WysiwygEngine?

    /// What an untouched draft shows (design board ㉝ E): `title` faint in the
    /// title heading's face right where the typed title will go, and `hint`
    /// on the line below. Drawn only while the text is still the draft's
    /// empty heading, so it disappears with the first keystroke.
    struct DraftPlaceholder: Equatable {
        var title: String
        var hint: String
    }
    private var isRestyling = false

    /// Font/line-height the cached `engine` was built for. The engine compiles
    /// ~9 regular expressions, so we rebuild it only when these actually change
    /// instead of on every SwiftUI `updateNSView` pass.
    private var engineFontSize: CGFloat = .nan
    private var engineLineHeight: CGFloat = .nan
    private var engineFontName: String = ""

    /// Set when a coalesced restyle is already queued for this runloop turn, so
    /// a burst of async triggers (e.g. many remote images finishing) collapses
    /// into a single full restyle instead of one per event.
    private var restyleScheduled = false

    /// Test instrumentation: number of full restyles and engine rebuilds.
    private(set) var restyleCount = 0
    private(set) var engineBuildCount = 0

    // MARK: - Layout

    /// The user's "Editor Width" preference ("narrow" / "medium" / "wide"),
    /// driving `maxColumnWidth` so the readable column width is configurable and
    /// stays stable across sidebar toggles.
    var editorWidth: String = "medium"

    /// Maximum readable text column width in points, resolved from the
    /// `editorWidth` preference. Exposed as a static resolver so the split-view
    /// detail column can enforce a matching minimum width (see `AppShellView`).
    static func columnWidth(for setting: String) -> CGFloat {
        switch setting {
        case "narrow": return 600
        case "wide": return 860
        default: return 680
        }
    }

    var maxColumnWidth: CGFloat { Self.columnWidth(for: editorWidth) }

    /// Minimum horizontal inset on each side of the text column. Lowered from
    /// 90 → 40 so the capped column engages at a smaller pane width
    /// (cap + 2×inset), keeping the text column stable across sidebar toggles
    /// on more window sizes.
    static let minSideInset: CGFloat = 40

    /// Horizontal text inset that centers a `maxColumnWidth`-capped column in a
    /// text view of the given available width. The scroll view itself spans the
    /// full width (so its scroller hugs the right edge); this inset reproduces
    /// the centered column purely inside the text view.
    func sideInset(forAvailableWidth width: CGFloat) -> CGFloat {
        max(Self.minSideInset, (width - maxColumnWidth) / 2)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setupEditor()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupEditor() {
        isEditable = true
        isSelectable = true
        isRichText = true
        allowsUndo = true
        usesAdaptiveColorMappingForDarkAppearance = true
        font = WysiwygEngine.resolveFont(name: fontName, size: fontSize)
        textColor = NSColor(named: "PrimaryText")
        backgroundColor = .clear
        insertionPointColor = NSColor(Color.accent)
        autoresizingMask = [.width]
        // Top/bottom breathing room for the text column; the scroll view adds
        // the toolbar's height on top when it extends under it.
        textContainerInset = NSSize(width: 0, height: 30)
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: max(bounds.width, 1), height: CGFloat.greatestFiniteMagnitude)
        textContainer?.lineFragmentPadding = 0
        isHorizontallyResizable = false
        isVerticallyResizable = true
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        rebuildEngine()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleImageDidLoad),
            name: .imageDidLoad,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAnimatedImageFrameDidChange(_:)),
            name: .animatedImageFrameDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollToHeading(_:)),
            name: .scrollToHeading,
            object: nil
        )
    }

    // MARK: - Heading navigation

    /// Ensures the text view's frame is tall enough to contain all laid-out
    /// content. Without this, `NSClipView.scroll(to:)` is clamped to the
    /// document view's bounds — if the frame only matches the visible height,
    /// no scrolling is possible and every heading jump lands at the top.
    func fitFrameToContent() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = usedRect.height + textContainerInset.height * 2
        let minHeight = enclosingScrollView?.contentSize.height ?? bounds.height
        let targetHeight = max(requiredHeight, minHeight)
        if abs(frame.height - targetHeight) > 0.5 {
            setFrameSize(NSSize(width: frame.width, height: targetHeight))
        }
    }

    /// Last frame width we applied the column inset for. The `setFrameSize`
    /// override uses this to recompute the capping inset only when the width
    /// actually changes — not on every height tick from `fitFrameToContent`,
    /// which would otherwise loop.
    private var lastLayoutWidth: CGFloat = -1

    /// Recomputes the centered/capped side inset whenever the text view's width
    /// changes. `widthTracksTextView = true` auto-tracks the text container's
    /// width to the text view bounds, but it does NOT recompute the capping
    /// inset — so without this, collapsing/expanding the sidebar reflows the
    /// text against a stale inset (the column width changes even though only
    /// the pane width did). SwiftUI does not call `updateNSView` on a pure pane
    /// resize, so this override is the only path that fires on sidebar toggle.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let width = newSize.width
        guard abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        recomputeColumnInset()
    }

    private func recomputeColumnInset() {
        let width = max(bounds.width, 1)
        let inset = sideInset(forAvailableWidth: width)
        guard abs(textContainerInset.width - inset) > 0.5 else { return }
        textContainerInset = NSSize(width: inset, height: textContainerInset.height)
        // The container auto-tracks to bounds.width - 2*inset; relayout and grow
        // the frame height to fit the (possibly re-wrapped) content.
        fitFrameToContent()
    }

    /// Character ranges of every Markdown heading line (`#`…`######`), in
    /// document order, skipping fenced code blocks. The N-th element is the
    /// scroll target for outline row N. Static + pure so it can be unit-tested.
    static func headingLineRanges(in string: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var inCodeBlock = false
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byLines]) { sub, range, _, _ in
            let trimmed = (sub ?? "").trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCodeBlock.toggle()
                return
            }
            if inCodeBlock { return }
            if trimmed.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil {
                ranges.append(range)
            }
        }
        return ranges
    }

    @objc private func handleScrollToHeading(_ notification: Notification) {
        // Only the key window's editor responds to outline navigation. The
        // `.scrollToHeading` notification is posted with `object: nil`, so
        // without this guard every open window's editor would scroll when an
        // outline row is clicked in any one of them. Clicking the rail makes
        // the clicked window key, so this filters to exactly that window.
        guard window?.isKeyWindow == true else { return }
        guard let index = notification.userInfo?["index"] as? Int,
              let storage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let ranges = Self.headingLineRanges(in: storage.string as NSString)
        guard index >= 0, index < ranges.count else { return }
        let target = ranges[index]

        // Grow the text view to fit all content, then force layout so the
        // heading's rect is valid before we measure it.
        fitFrameToContent()
        layoutManager.ensureLayout(for: textContainer)

        // Heading rect in the text view's coordinate space.
        let glyphRange = layoutManager.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        // Bias the heading toward the TOP of the viewport: reveal a viewport-tall
        // region starting just above it. scrollToVisible top-aligns an oversized
        // rect and clamps at the document edges on its own, so this works
        // regardless of clip-view flippedness (the manual clip math did not).
        let viewportHeight = enclosingScrollView?.contentView.bounds.height ?? rect.height
        let topMargin: CGFloat = 12
        let revealRect = NSRect(x: rect.minX,
                                y: max(0, rect.minY - topMargin),
                                width: max(1, rect.width),
                                height: max(rect.height, viewportHeight))
        scrollToVisible(revealRect)
    }

    /// The caret takes its height from the neighboring character's font,
    /// which is tiny next to collapsed Markdown syntax. Never draw it shorter
    /// than a body line.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var rect = rect
        let minHeight = ceil(fontSize * 1.25)
        if rect.height < minHeight {
            rect.origin.y = rect.maxY - minHeight
            rect.size.height = minHeight
        }
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        // Widen caret invalidation to match the taller caret drawn above, so
        // blinking off erases all of it.
        var rect = invalidRect
        if rect.width <= 3 {
            rect = rect.insetBy(dx: 0, dy: -fontSize)
        }
        super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
    }

    // MARK: - Pasting and dropping media

    /// Pasted or dropped images and videos are copied into the library's
    /// `attachments/` folder and linked on their own line (AttachmentImport);
    /// anything else pastes and drops as before.
    override func paste(_ sender: Any?) {
        if insertMedia(from: .general, replacing: selectedRange()) { return }
        super.paste(sender)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL]
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingEntered(sender)
        return mediaFiles(on: sender.draggingPasteboard).isEmpty ? operation : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingUpdated(sender)
        return mediaFiles(on: sender.draggingPasteboard).isEmpty ? operation : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        let location = characterIndexForInsertion(at: point)
        if insertMedia(from: sender.draggingPasteboard, replacing: NSRange(location: location, length: 0)) {
            return true
        }
        return super.performDragOperation(sender)
    }

    private func mediaFiles(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter(AttachmentImport.isMedia)
    }

    /// Image data on the pasteboard (a screenshot, an image copied from a
    /// browser) in its own format where it has one, else as PNG. Skipped when
    /// there is text too: Word and Pages put a picture of copied text there.
    private func pastedImage(on pasteboard: NSPasteboard) -> (data: Data, ext: String)? {
        guard pasteboard.string(forType: .string) == nil else { return nil }
        let native: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "png"), (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
            (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
        ]
        for (type, ext) in native {
            if let data = pasteboard.data(forType: type) { return (data, ext) }
        }
        guard let tiff = pasteboard.data(forType: .tiff),
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        return (png, "png")
    }

    private func insertMedia(from pasteboard: NSPasteboard, replacing range: NSRange) -> Bool {
        guard let library = ImageLoader.shared.workspaceURL else { return false }
        let hasFiles = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        var imported: [URL] = []
        if hasFiles {
            imported = mediaFiles(on: pasteboard).compactMap { try? AttachmentImport.importFile($0, into: library) }
        } else if let image = pastedImage(on: pasteboard),
                  let url = try? AttachmentImport.saveImage(image.data, ext: image.ext, into: library) {
            imported = [url]
        }
        guard !imported.isEmpty else { return false }

        let noteFolder = ImageLoader.shared.baseURL ?? library
        var text = imported
            .map { AttachmentImport.markdown(forPath: AttachmentImport.relativePath(from: noteFolder, to: $0)) }
            .joined(separator: "\n")
        // Each embed on a line of its own.
        let ns = string as NSString
        let start = min(range.location, ns.length)
        let end = min(NSMaxRange(range), ns.length)
        if start > 0, ns.character(at: start - 1) != 0x0A { text = "\n" + text }
        if end < ns.length, ns.character(at: end) != 0x0A { text += "\n" }
        window?.makeFirstResponder(self)
        insertText(text, replacementRange: NSRange(location: start, length: end - start))
        return true
    }

    // MARK: - First responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { restyle() }
        return result
    }

    /// Check if this text view is currently the window's first responder.
    func isFirstResponder() -> Bool {
        return window?.firstResponder == self
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Diag.log("viewDidMoveToWindow window=\(window != nil) frame=\(frame) isEditable=\(isEditable)")
        if window != nil { restyle() }
        if window != nil, focusesOnAppear {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
                self.setSelectedRange(NSRange(location: (self.string as NSString).length, length: 0))
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let placeholder = draftPlaceholder, string == FileNoteStore.draftContent,
              let layoutManager, let textContainer else { return }
        // Just past the (possibly hidden) "# ", on the heading's line.
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: 2), actualCharacterRange: nil)
        let line = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let marks = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        let origin = textContainerOrigin
        let faint = NSColor(Color.faintIcon)

        let titleFont = WysiwygEngine.resolveFont(name: fontName, size: 30, weight: .semibold)
        let title = NSAttributedString(string: placeholder.title,
                                       attributes: [.font: titleFont, .foregroundColor: faint])
        let titleY = origin.y + line.minY + max(0, (line.height - titleFont.ascender + titleFont.descender) / 2)
        title.draw(at: NSPoint(x: origin.x + marks.maxX, y: titleY))

        let hintFont = WysiwygEngine.resolveFont(name: fontName, size: fontSize)
        let hint = NSAttributedString(string: placeholder.hint,
                                      attributes: [.font: hintFont, .foregroundColor: faint])
        hint.draw(at: NSPoint(x: origin.x + line.minX, y: origin.y + line.maxY + 14))
    }

    private func rebuildEngine() {
        // The accent is read here; an accent change rebuilds the window
        // (WindowRoot's .id), so the editor picks up the new color.
        let style = WysiwygEngine.makeStyle(fontSize: fontSize, lineHeight: lineHeight, fontName: fontName,
                                            strongColor: MarkdownPalette.strong(accentHex: AppSettings.accentColorHex))
        engine = WysiwygEngine(style: style)
        engineFontSize = fontSize
        engineLineHeight = lineHeight
        engineFontName = fontName
        engineBuildCount += 1
        typingAttributes = style.baseParagraph
    }

    func rebuildEngineAndRestyle() {
        rebuildEngine()
        restyle()
    }

    /// Rebuild the styling engine + restyle only when the font size or line
    /// height actually changed. Called from `updateNSView`, which SwiftUI may
    /// invoke many times for reasons unrelated to editor styling.
    func rebuildEngineAndRestyleIfNeeded() {
        if engine == nil || engineFontSize != fontSize || engineLineHeight != lineHeight || engineFontName != fontName {
            rebuildEngineAndRestyle()
        }
    }

    // MARK: - Text changes

    override func didChangeText() {
        super.didChangeText()
        if isRestyling { return }
        Diag.log("didChangeText string='\(string.prefix(30))'")
        restyle()
        onTextChange?(markdownString())
    }

    /// Request a restyle that is coalesced to at most once per runloop turn.
    /// Used by asynchronous triggers (remote image loads) that can fire in
    /// rapid bursts while the user is scrolling. Without coalescing, each event
    /// would run a full O(document) restyle on the main thread → beachball.
    func setNeedsRestyle() {
        if restyleScheduled { return }
        restyleScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restyleScheduled = false
            self.restyle()
        }
    }

    func restyle() {
        if isRestyling { return }
        guard let storage = textStorage else { return }
        isRestyling = true
        restyleCount += 1
        defer { isRestyling = false }

        // Restyling briefly expands every image / video / table attachment
        // back to its (much shorter) Markdown source, which shrinks the
        // document and lets the clip view clamp the scroll offset. Remember
        // where the reader was and put them back afterwards.
        let clipView = enclosingScrollView?.contentView
        let savedScrollOrigin = clipView?.bounds.origin
        // Where the caret's line sits in the viewport. A restyle can change
        // heights above it (an image's source revealed, a table opening as
        // source); keeping this line still keeps the text under the pointer.
        let caretOffset: CGFloat? = {
            guard let clipView, let y = caretLineY() else { return nil }
            let offset = y - clipView.bounds.minY
            return (0...clipView.bounds.height).contains(offset) ? offset : nil
        }()

        // Map the caret into raw-markdown coordinates BEFORE collapsing/expanding
        // attachments, so it survives the coordinate change (image syntax ↔
        // attachment, table source ↔ grid).
        let rawCursor = rawLocation(forDisplayLocation: selectedRange().location)
        let rawMarkdown = markdownString()
        if rawMarkdown != storage.string {
            storage.setAttributedString(NSAttributedString(string: rawMarkdown))
        }
        let rawNS = rawMarkdown as NSString
        let clampedRaw = min(rawCursor, rawNS.length)

        // The table / math span the caret is inside (by ordinal index in
        // document order) stays editable source; all others render. Ordinal
        // indexing is stable because image collapsing never adds or removes
        // tables or math spans.
        let tables = MarkdownTableParser.tables(in: rawNS)
        var activeTableIndex = -1
        for (i, t) in tables.enumerated() where NSLocationInRange(clampedRaw, t.range) || clampedRaw == NSMaxRange(t.range) {
            activeTableIndex = i
            break
        }

        let mathSpans = LatexMath.mathSpans(in: rawNS, excludingTableRanges: tables.map { $0.range })
        var activeMathIndex = -1
        for (i, s) in mathSpans.enumerated() where NSLocationInRange(clampedRaw, s.range) || clampedRaw == NSMaxRange(s.range) {
            activeMathIndex = i
            break
        }

        let contentWidth = max(120, (textContainer?.size.width ?? bounds.width))
        engine?.applyStyle(to: storage, cursorLocation: clampedRaw,
                           activeTableIndex: activeTableIndex, activeMathIndex: activeMathIndex,
                           maxWidth: contentWidth)

        // Map the caret back into the (re-collapsed) display coordinates.
        let displayCursor = displayLocation(forRawLocation: clampedRaw)
        setSelectedRange(NSRange(location: min(displayCursor, storage.length), length: 0))

        if let clipView, var target = savedScrollOrigin {
            fitFrameToContent()
            if let caretOffset, let y = caretLineY() {
                target.y = y - caretOffset
            }
            if clipView.bounds.origin != target {
                clipView.setBoundsOrigin(clipView.constrainBoundsRect(
                    NSRect(origin: target, size: clipView.bounds.size)).origin)
                enclosingScrollView?.reflectScrolledClipView(clipView)
            }
        }

        repositionVideoPlayers()

        // Text typed next inherits the attributes before the caret; if that is
        // collapsed syntax (a 0.1pt font), fall back to the body style.
        if let font = typingAttributes[.font] as? NSFont, font.pointSize < 1 {
            typingAttributes = WysiwygEngine.makeStyle(fontSize: fontSize, lineHeight: lineHeight, fontName: fontName).baseParagraph
        }
    }

    /// Top of the caret's line fragment, in view coordinates.
    private func caretLineY() -> CGFloat? {
        guard let layoutManager, let storage = textStorage else { return nil }
        let location = selectedRange().location
        let rect: NSRect
        if location >= storage.length, !layoutManager.extraLineFragmentRect.isEmpty {
            rect = layoutManager.extraLineFragmentRect
        } else if storage.length > 0 {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(location, storage.length - 1))
            rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        } else {
            return nil
        }
        return rect.minY + textContainerOrigin.y
    }

    @objc private func handleImageDidLoad() {
        setNeedsRestyle()
    }

    @objc private func handleAnimatedImageFrameDidChange(_ notification: Notification) {
        guard let animatedAttachment = notification.object as? ImageTextAttachment,
              let storage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else {
            return
        }
        // Redraw only the rect occupied by the animated attachment, and only if
        // it is currently on-screen. Avoids invalidating the entire text view /
        // scroll content on every GIF frame, which would compete with scrolling.
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard let attachment = value as? ImageTextAttachment, attachment === animatedAttachment else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textContainerInset.width
            rect.origin.y += textContainerInset.height
            if rect.intersects(visibleRect) {
                setNeedsDisplay(rect)
            }
            stop.pointee = true
        }
    }

    private func markdownString() -> String {
        guard let storage = textStorage else { return string }
        let result = NSMutableString(string: storage.string)
        var replacements: [(range: NSRange, markdown: String)] = []

        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? MarkdownBackedAttachment else { return }
            replacements.append((range, attachment.markdownSource))
        }

        for replacement in replacements.reversed() {
            result.replaceCharacters(in: replacement.range, with: replacement.markdown)
        }

        return result as String
    }

    // MARK: - Raw ↔ display coordinate mapping
    //
    // The storage holds collapsed attachments (images / table grids), each one
    // character standing in for a multi-character markdown source. These helpers
    // convert between the displayed storage offsets and the raw-markdown offsets
    // so the caret survives the collapse/expand that happens on every restyle.

    /// Raw-markdown offset corresponding to a location in the current storage.
    func rawLocation(forDisplayLocation displayLocation: Int) -> Int {
        guard let storage = textStorage else { return displayLocation }
        let clamped = min(max(0, displayLocation), storage.length)
        return CursorMapping.rawLocation(forDisplayLocation: clamped, segments: segments(from: storage))
    }

    /// Display offset (in the collapsed storage) corresponding to a raw-markdown
    /// offset. A raw location inside a collapsed attachment snaps to just before
    /// it; one at the attachment's trailing boundary maps to just after it.
    func displayLocation(forRawLocation rawLocation: Int) -> Int {
        guard let storage = textStorage else { return rawLocation }
        return CursorMapping.displayLocation(forRawLocation: rawLocation,
                                             segments: segments(from: storage),
                                             displayTotal: storage.length)
    }

    /// Break the live storage into the run model `CursorMapping` operates on:
    /// each collapsed attachment becomes one `.attachment` segment (display
    /// length 1, raw length = its markdown source), and every other run becomes a
    /// `.text` segment.
    private func segments(from storage: NSTextStorage) -> [CursorMapping.Segment] {
        var result: [CursorMapping.Segment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            if let attachment = value as? MarkdownBackedAttachment {
                result.append(.attachment(rawLength: (attachment.markdownSource as NSString).length))
            } else {
                result.append(.text(range.length))
            }
        }
        return result
    }

    // MARK: - Mouse / cursor tracking

    /// Moving the caret with the keyboard re-renders too, so the syntax of the
    /// line it lands on (an image's source, a heading's `##`) is revealed the
    /// same way a click reveals it.
    override func keyDown(with event: NSEvent) {
        let before = selectedRange()
        super.keyDown(with: event)
        let navigationKeys: Set<NSEvent.SpecialKey> = [.upArrow, .downArrow, .leftArrow, .rightArrow,
                                                       .home, .end, .pageUp, .pageDown]
        guard let key = event.specialKey, navigationKeys.contains(key),
              !event.modifierFlags.contains(.shift), let storage = textStorage else { return }
        var after = selectedRange()
        guard after.length == 0 else { return }

        // A revealed image follows its source but stands for no raw text, so
        // both of its edges map back to the end of the source. Moving forward
        // from there steps over it (and its line break) to the next line.
        func revealedImage(at index: Int) -> Bool {
            guard index >= 0, index < storage.length,
                  let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil)
                      as? MarkdownBackedAttachment else { return false }
            return attachment.markdownSource.isEmpty
        }
        // Right arrow: from just before the image. Down arrow: from anywhere
        // on its source line, landing on either edge of the image.
        let image: Int? = switch key {
        case .rightArrow where revealedImage(at: before.location) && after.location <= before.location + 1:
            before.location
        case .downArrow where revealedImage(at: after.location) && after.location >= before.location:
            after.location
        case .downArrow where revealedImage(at: after.location - 1) && after.location > before.location:
            after.location - 1
        default:
            nil
        }
        if let image {
            var next = image + 1
            if next < storage.length, (storage.string as NSString).character(at: next) == 0x0A {
                next += 1
            }
            after = NSRange(location: next, length: 0)
            setSelectedRange(after)
        }
        if after != before {
            restyle()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let window = window, window.firstResponder != self {
            window.makeFirstResponder(self)
        }
        if toggleTaskIfCheckboxClicked(event) { return }
        if playVideoIfClicked(event) { return }
        if revealImageSourceIfClicked(event) { return }
        super.mouseDown(with: event)
        // A simple click (no drag-selection): re-render so the table the caret
        // landed in opens as editable source, and the one it left re-renders as a
        // grid. Skipped when a range is selected so a drag-selection isn't
        // clobbered. The caret survives the storage rebuild via the raw↔display
        // remap in restyle().
        if selectedRange().length == 0 {
            restyle()
        }
    }

    /// To-do checkboxes are drawn in the list indent (the `[ ]` syntax is
    /// collapsed), so a click on one is handled here: it flips `[ ]` ↔ `[x]`
    /// on that line instead of placing the caret.
    private func toggleTaskIfCheckboxClicked(_ event: NSEvent) -> Bool {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = min(layoutManager.characterIndexForGlyph(at: glyphIndex), storage.length - 1)
        let string = storage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: charIndex, length: 0))
        guard let marker = storage.attribute(.listMarker, at: lineRange.location, effectiveRange: nil) as? ListMarker,
              case .task = marker.kind else { return false }

        let firstGlyph = layoutManager.glyphIndexForCharacter(at: lineRange.location)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
        let baseline = fragment.minY + layoutManager.location(forGlyphAt: firstGlyph).y
        guard marker.checkboxRect(baselineY: baseline).insetBy(dx: -4, dy: -4).contains(containerPoint) else { return false }

        let line = string.substring(with: lineRange) as NSString
        guard let regex = try? NSRegularExpression(pattern: #"\[([ xX])\]"#),
              let match = regex.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) else { return false }
        let mark = line.substring(with: match.range(at: 1))
        let target = NSRange(location: lineRange.location + match.range(at: 1).location, length: 1)
        guard shouldChangeText(in: target, replacementString: mark == " " ? "x" : " ") else { return true }
        storage.replaceCharacters(in: target, with: mark == " " ? "x" : " ")
        didChangeText()
        return true
    }

    // MARK: - Inline video

    /// Players opened over video cards, keyed by attachment. The engine reuses
    /// a card's attachment object across restyles, so a player can follow its
    /// card as the text re-lays out.
    private var videoPlayers: [ObjectIdentifier: (attachment: VideoAttachment, view: AVPlayerView)] = [:]

    private func playVideoIfClicked(_ event: NSEvent) -> Bool {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < storage.length,
              let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? VideoAttachment,
              let frame = videoFrame(at: charIndex, attachment: attachment), frame.contains(point) else { return false }

        let id = ObjectIdentifier(attachment)
        if let existing = videoPlayers[id] {
            existing.view.player?.play()
            return true
        }
        let playerView = AVPlayerView(frame: frame)
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.wantsLayer = true
        playerView.layer?.cornerRadius = 8
        playerView.layer?.masksToBounds = true
        playerView.player = AVPlayer(url: attachment.fileURL)
        addSubview(playerView)
        videoPlayers[id] = (attachment, playerView)
        playerView.player?.play()
        return true
    }

    /// A click on an image puts the caret at the end of its Markdown source
    /// (restyle then shows the source above the image, as in Obsidian's live
    /// preview) instead of selecting the attachment character — which tinted
    /// the whole image with the selection color.
    private func revealImageSourceIfClicked(_ event: NSEvent) -> Bool {
        guard event.clickCount == 1, !event.modifierFlags.contains(.shift),
              let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < storage.length,
              let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? ImageTextAttachment
        else { return false }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        guard rect.contains(point) else { return false }

        // A collapsed image stands for its whole source, so "after it" is the
        // source's end; a revealed one follows its source, so "before it" is.
        let caret = attachment.markdownSource.isEmpty ? charIndex : charIndex + 1
        setSelectedRange(NSRange(location: caret, length: 0))
        restyle()
        return true
    }

    /// The poster area of the video card at `charIndex`, in view coordinates.
    /// Attachments sit on the baseline, so the card's top is baseline − height.
    private func videoFrame(at charIndex: Int, attachment: VideoAttachment) -> NSRect? {
        guard let layoutManager else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: charIndex)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let location = layoutManager.location(forGlyphAt: glyph)
        let size = layoutManager.attachmentSize(forGlyphAt: glyph)
        guard size.width > 0 else { return nil }
        let origin = NSPoint(x: fragment.minX + location.x + textContainerOrigin.x,
                             y: fragment.minY + location.y - size.height + textContainerOrigin.y)
        return NSRect(origin: origin, size: attachment.videoRect.size)
    }

    /// Keeps open players on their cards after a restyle; closes players whose
    /// card is gone (deleted, or switched to its raw source).
    private func repositionVideoPlayers() {
        guard !videoPlayers.isEmpty, let storage = textStorage else { return }
        var located: [ObjectIdentifier: Int] = [:]
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let video = value as? VideoAttachment { located[ObjectIdentifier(video)] = range.location }
        }
        if let layoutManager, let textContainer { layoutManager.ensureLayout(for: textContainer) }
        for (id, entry) in videoPlayers {
            if let index = located[id], let frame = videoFrame(at: index, attachment: entry.attachment) {
                entry.view.frame = frame
            } else {
                entry.view.player?.pause()
                entry.view.removeFromSuperview()
                videoPlayers[id] = nil
            }
        }
    }

    // MARK: - Formatting commands

    @objc func toggleBold(_ sender: Any?) {
        wrapSelection(prefix: "**", suffix: "**")
    }

    @objc func toggleItalic(_ sender: Any?) {
        wrapSelection(prefix: "*", suffix: "*")
    }

    @objc func wrapSelection(prefix: String, suffix: String) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        if range.length == 0 {
            storage.insert(NSAttributedString(string: "\(prefix)\(suffix)"), at: range.location)
            setSelectedRange(NSRange(location: range.location + prefix.count, length: 0))
        } else {
            let selectedText = (storage.string as NSString).substring(with: range)
            let replacement = NSAttributedString(string: "\(prefix)\(selectedText)\(suffix)")
            storage.replaceCharacters(in: range, with: replacement)
            setSelectedRange(NSRange(location: range.location, length: replacement.length))
        }
        didChangeText()
    }

    @objc func insertLink() {
        wrapSelection(prefix: "[", suffix: "](url)")
    }

    @objc func toggleTodoOnCurrentLine() {
        guard let storage = textStorage else { return }
        let cursor = selectedRange().location
        let lineRange = (storage.string as NSString).lineRange(for: NSRange(location: cursor, length: 0))
        let line = (storage.string as NSString).substring(with: lineRange)

        guard let regex = try? NSRegularExpression(pattern: #"\[([ xX])\]"#) else { return }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else { return }

        let checkboxChar = nsLine.substring(with: match.range(at: 1))
        let newChar = (checkboxChar == " ") ? "x" : " "
        let absRange = NSRange(location: lineRange.location + match.range(at: 1).location, length: 1)
        storage.replaceCharacters(in: absRange, with: newChar)
        didChangeText()
    }
}
