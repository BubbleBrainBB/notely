import SwiftUI

struct EditorView: View {
    let note: FileNote
    @Environment(FileNoteStore.self) var store
    @Environment(AppModel.self) var appModel
    @State private var displayedText: String
    /// The content the editor last loaded or saved — its view of what is on disk.
    /// Used to tell an unsaved local edit apart from an external change.
    @State private var lastSyncedContent: String
    @State private var liveWordCount: Int
    @State private var liveCharCount: Int
    @State private var saveTask: Task<Void, Never>? = nil

    @AppStorage("notely.editorFont") private var editorFontName: String = "System"
    @AppStorage("notely.editorWidth") private var editorWidth: String = "medium"
    @AppStorage("notely.editorLineHeight") private var editorLineHeight: Double = 1.7
    @AppStorage(AppSettings.fontSizeKey) private var editorFontSize = AppSettings.defaultEditorFontSize
    @AppStorage(AppSettings.spellCheckKey) private var spellCheck = AppSettings.defaultSpellCheck
    @AppStorage(AppSettings.smartPunctuationKey) private var smartPunctuation = AppSettings.defaultSmartPunctuation

    private var fontSize: CGFloat { CGFloat(editorFontSize) }
    private var lineHeight: CGFloat { CGFloat(editorLineHeight) }
    private var fontName: String { editorFontName }

    /// Outline derived from the live text. Uses the exact same heading detection
    /// as `WysiwygTextView.headingLineRanges`, so a row's `index` always maps to
    /// the correct heading when the rail posts `.scrollToHeading`.
    private var outlineHeadings: [OutlineHeading] {
        let ns = displayedText as NSString
        return WysiwygTextView.headingLineRanges(in: ns).enumerated().map { i, range in
            let line = ns.substring(with: range).trimmingCharacters(in: .whitespaces)
            let level = line.prefix(while: { $0 == "#" }).count
            let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
            return OutlineHeading(index: i, level: level, text: String(text))
        }
    }

    /// A blank page not yet on disk (design board ㉝ E): shows a placeholder,
    /// takes focus, and becomes a note in the library at its first save.
    var isDraft = false

    init(note: FileNote, isDraft: Bool = false) {
        self.note = note
        self.isDraft = isDraft
        let initialText = note.content
        _displayedText = State(initialValue: initialText)
        _lastSyncedContent = State(initialValue: initialText)
        _liveWordCount = State(initialValue: Self.wordCount(in: initialText))
        _liveCharCount = State(initialValue: initialText.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                WysiwygEditor(
                    initialText: displayedText,
                    fontSize: fontSize,
                    lineHeight: lineHeight,
                    fontName: fontName,
                    editorWidth: editorWidth,
                    spellCheck: spellCheck,
                    smartPunctuation: smartPunctuation,
                    draftPlaceholder: isDraft
                        ? .init(title: "Title", hint: "Start typing — the note is saved once you write something.")
                        : nil,
                    focusesOnAppear: isDraft,
                    onTextChange: handleTextChange
                )
                .frame(maxWidth: .infinity)
                .background(Color.editorBg)

                // Navigation lives at the right edge: a thin tick rail that
                // expands to a clickable outline on hover. It never covers the
                // centered text and is independent of the info popover.
                OutlineRail(headings: outlineHeadings)
            }
        }
        .background(Color.editorBg)
        .modifier(isDraft
                  ? NoteToolbar(emptyTitle: "New Note")
                  : NoteToolbar(note: note, wordCount: liveWordCount, charCount: liveCharCount))
        .onAppear {
            loadNote()
        }
        .onChange(of: note.id) { _, _ in
            loadNote()
        }
        // The open file changed on disk (external editor → store reload). Pull it
        // in live, unless the user has unsaved local edits that would be lost.
        .onChange(of: note.content) { _, newContent in
            adoptExternalChangeIfClean(newContent)
        }
    }

    private func loadNote() {
        saveTask?.cancel()
        ImageLoader.shared.setBaseURL(note.url.deletingLastPathComponent())
        displayedText = note.content
        lastSyncedContent = note.content
        updateCounts(from: note.content)
    }

    /// Reconcile an on-disk change to the currently open note with the editor.
    private func adoptExternalChangeIfClean(_ newContent: String) {
        switch ExternalSync.resolve(disk: newContent, displayed: displayedText, lastSynced: lastSyncedContent) {
        case .ignore:
            lastSyncedContent = newContent
        case .adopt:
            displayedText = newContent
            lastSyncedContent = newContent
            updateCounts(from: newContent)
        case .keepLocal:
            break
        }
    }

    private func handleTextChange(_ newText: String) {
        displayedText = newText
        updateCounts(from: newText)
        scheduleSave(newText)
    }

    private func updateCounts(from text: String) {
        liveWordCount = Self.wordCount(in: text)
        liveCharCount = text.count
    }

    private static func wordCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? 0 : trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    private func scheduleSave(_ content: String) {
        // Bind the destination to the note this text came from, at schedule time,
        // so a debounced write can never be redirected to a note switched-to
        // during the 500ms window.
        let targetId = note.id
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            // A draft's first save puts it in the library: select it there.
            if store.saveContent(content, to: targetId), appModel.selectedNoteId == nil {
                appModel.selectedNoteId = targetId
            }
        }
    }

}

/// The window toolbar for the editor: the note's title and location in the
/// title area, note actions as system toolbar buttons (Liquid Glass on
/// macOS 26+). With `note == nil` only New Note is offered.
struct NoteToolbar: ViewModifier {
    var note: FileNote? = nil
    var wordCount = 0
    var charCount = 0
    /// The title shown when there's no note.
    var emptyTitle = "Notes"
    @Environment(AppModel.self) var appModel
    @Environment(FileNoteStore.self) var store
    @State private var showsInfo = false

    /// The file name: notes are files, and clipped articles often have no
    /// heading, so their first line makes a poor title.
    private var title: String {
        note?.filename ?? emptyTitle
    }

    /// "Clippings / AI · Edited Oct 9"
    private var subtitle: String {
        guard let note else { return "" }
        let folder = note.relativePath.split(separator: "/").joined(separator: " / ")
        let edited = Self.editedLabel(for: note.updatedAt)
        return folder.isEmpty ? edited : "\(folder) · \(edited)"
    }

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .modifier(RemovesSystemTitle())
            .toolbar {
                NoteTitleHeader(title: title, subtitle: subtitle)

                // Flat 拾页 glyphs, each its own item with the shared glass
                // capsule turned off — the same treatment as the sidebar
                // toggle, so the page's corner holds plain icons, not a pill.
                FlatToolbarItem {
                    Button {
                        appModel.openNote(store.createNote()?.id)
                    } label: {
                        Label {
                            Text("New Note")
                        } icon: {
                            Image(nsImage: ShiyeGlyph.newNote.templateImage())
                        }
                    }
                    .help("New Note (⌘N)")
                }

                if let note {
                    FlatToolbarItem {
                        Button {
                            showsInfo.toggle()
                        } label: {
                            Label {
                                Text("Info")
                            } icon: {
                                Image(nsImage: ShiyeGlyph.info.templateImage())
                            }
                        }
                        .help("Note Info")
                        .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
                            DocumentInfoPopover(note: note, wordCount: wordCount, charCount: charCount)
                        }
                    }

                    FlatToolbarItem {
                        Menu {
                            Button(note.pinned ? "Unpin" : "Pin") { store.togglePin(note.id) }
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                appModel.selectedNoteId = nil
                                store.deleteNote(note.id)
                            }
                        } label: {
                            Label {
                                Text("More")
                            } icon: {
                                Image(nsImage: ShiyeGlyph.more.templateImage())
                            }
                        }
                        .menuIndicator(.hidden)
                        .help("More")
                    }
                }
            }
    }

    /// "Edited 14:20" today, "Edited yesterday 09:12", else "Edited Oct 8".
    static func editedLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Edited \(time)" }
        if calendar.isDateInYesterday(date) { return "Edited yesterday \(time)" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = sameYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
        return "Edited \(day)"
    }
}

/// A toolbar item drawn bare: on macOS 26 the shared Liquid Glass
/// background is hidden (see SidebarToggleItem).
struct FlatToolbarItem<Content: View>: ToolbarContent {
    /// `.automatic` lines up at the trailing edge, after the title's spacer;
    /// `.primaryAction` would pull the icons to the leading side on macOS.
    var placement: ToolbarItemPlacement = .automatic
    @ViewBuilder let content: () -> Content

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: placement, content: content)
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement, content: content)
        }
    }
}

/// The note's file name over the page (design board ㉙ B + H3): set in the
/// editor's own body face — New York with 宋体 by default, through the same
/// composite pairing as the text — at medium weight in secondary gray, so it
/// reads as the page's running head rather than outshouting it. The edit
/// date stays small sans in faint gray. The window keeps its plain title
/// for the Window menu; only the toolbar shows this one. Needs macOS 26 for
/// the flexible spacer that keeps the icons at the trailing edge once the
/// system title is gone; older systems keep the system title.
struct NoteTitleHeader: ToolbarContent {
    let title: String
    let subtitle: String
    @AppStorage("notely.editorFont") private var editorFontName: String = "System"

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            FlatToolbarItem(placement: .navigation) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.styledTitle(title, fontName: editorFontName))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.notely(11))
                            .foregroundColor(.faintText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.leading, 6)
            }
            ToolbarSpacer(.flexible)
        }
    }

    /// `title` in the body family at 13.5pt medium.
    static func styledTitle(_ title: String, fontName: String) -> AttributedString {
        BodyFace.text(title, fontName: fontName, size: 13.5, weight: .medium)
    }
}

/// Text set in a body face — the editor's, New York with 宋体 by default —
/// with Han runs re-set in the paired CJK face exactly as the editor does,
/// so serif UI text (the header title, the empty pages) reads like the page.
enum BodyFace {
    static func text(_ string: String, fontName: String, size: CGFloat,
                     weight: NSFont.Weight = .regular) -> AttributedString {
        let font = WysiwygEngine.resolveFont(name: fontName, size: size, weight: weight)
        let storage = NSTextStorage(string: string, attributes: [.font: font])
        CompositeFont(baseFont: font, familyName: fontName).apply(to: storage)

        var result = AttributedString()
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            var run = AttributedString(storage.attributedSubstring(from: range).string)
            run.font = Font((value as? NSFont ?? font) as CTFont)
            result += run
        }
        return result
    }
}

/// Hides the system's toolbar title where NoteTitleHeader replaces it.
private struct RemovesSystemTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

/// A heading in the document outline. `index` is the heading's ordinal in
/// document order, which is the payload used to scroll the editor.
struct OutlineHeading: Identifiable {
    let index: Int
    let level: Int
    let text: String
    var id: Int { index }
}

/// Lightweight, glanceable document info shown in a popover anchored to the
/// toolbar info button — stats and tags only (navigation lives in the rail).
struct DocumentInfoPopover: View {
    let note: FileNote
    let wordCount: Int
    let charCount: Int

    private var readingTime: String {
        let minutes = max(1, wordCount / 200)
        return "\(minutes) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                InspectorStatRow(label: "Words", value: "\(wordCount)")
                InspectorStatRow(label: "Characters", value: "\(charCount)")
                InspectorStatRow(label: "Reading time", value: readingTime)
                InspectorStatRow(label: "Created", value: note.createdAt.formatted(.dateTime.month().day().year()))
                InspectorStatRow(label: "Updated", value: note.updatedAt.formatted(.relative(presentation: .named)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            if !note.tags.isEmpty {
                InspectorDivider().padding(.horizontal, 0)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.tertiaryText)
                        .tracking(0.4)
                        .textCase(.uppercase)
                    FlowLayout(spacing: 6) {
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accent.opacity(0.08)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 240)
    }
}

/// Right-edge navigation: a thin column of tick marks (one per heading) that
/// expands on hover into a clickable outline. Clicking a row scrolls the editor
/// to that heading via the `.scrollToHeading` notification.
struct OutlineRail: View {
    let headings: [OutlineHeading]
    @State private var hovering = false

    var body: some View {
        if headings.isEmpty {
            Color.clear.frame(width: 0)
        } else {
            content
                .onHover { hovering = $0 }
                .animation(.easeInOut(duration: 0.15), value: hovering)
                .padding(.trailing, 18)
                .padding(.vertical, 16)
        }
    }

    @ViewBuilder private var content: some View {
        if hovering {
            expandedList
        } else {
            ticks
        }
    }

    private var ticks: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ForEach(headings) { h in
                Capsule()
                    .fill(Color.tertiaryText.opacity(0.45))
                    .frame(width: tickWidth(h.level), height: 2)
            }
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    private func tickWidth(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 18
        case 2: return 13
        default: return 9
        }
    }

    private var expandedList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Outline")
                    .font(.notely(11, weight: .semibold))
                    .foregroundColor(.tertiaryText)
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)

                ForEach(headings) { h in
                    OutlineRow(heading: h)
                }
            }
            .padding(10)
        }
        .frame(width: 240)
        .frame(maxHeight: 440)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, x: -3, y: 3)
    }
}

/// A single outline row with hover feedback. Clicking scrolls the editor to the
/// heading via `.scrollToHeading`.
private struct OutlineRow: View {
    let heading: OutlineHeading
    @State private var hovering = false

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .scrollToHeading, object: nil, userInfo: ["index": heading.index]
            )
        } label: {
            HStack(spacing: 6) {
                // A small level dot keeps the hierarchy legible without the
                // foreign "H1/H2" chips of the old inspector.
                Circle()
                    .fill(Color.accent.opacity(heading.level == 1 ? 0.55 : 0.28))
                    .frame(width: 4, height: 4)
                Text(heading.text)
                    .font(.notely(13, weight: heading.level == 1 ? .semibold : .regular))
                    .foregroundColor(hovering ? .accent : (heading.level == 1 ? .primaryText : .secondaryText))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.accentHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct InspectorStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primaryText)
                .lineLimit(1)
        }
    }
}

struct InspectorDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primaryText.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }
}

/// Simple flow layout for wrapping tag pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth && lineWidth > 0 {
                totalWidth = max(totalWidth, lineWidth)
                totalHeight += lineHeight + spacing
                lineWidth = size.width + spacing
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        totalWidth = max(totalWidth, lineWidth)
        totalHeight += lineHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .init(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
