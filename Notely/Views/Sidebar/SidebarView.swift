import SwiftUI
import AppKit

/// Left column (design boards ㉔–㉕, ㉚): search, then the library — its name
/// as the tree's heading that folds it, with folder options (…) and New
/// Note (+) on that line —
/// and Settings pinned to the bottom. No counts, no shortcut badges.
struct SidebarView: View {
    @Environment(AppModel.self) var appModel
    @Environment(FileNoteStore.self) var store
    @State private var expandedFolders: Set<String> = []
    /// The whole library folded under its header (design board ㉚ C).
    @AppStorage("notely.libraryCollapsed") private var libraryCollapsed = false

    /// Matches the trailing 8. (Was 22 while the hidden-title-bar window
    /// clipped ~14pt off the column's leading edge; the unified toolbar
    /// window doesn't.)
    static let leadingInset: CGFloat = 8

    private var sortedNotes: [FileNote] {
        NoteSorting.sorted(store.notes, by: appModel.sortMode)
    }

    var body: some View {
        list
        .frame(minWidth: 0, maxWidth: .infinity)
        // On the window ground, no divider: the editor's floating page is
        // what separates the two columns (design board ㉗ D).
        .background(Color.windowGround)
        // The hide button sits in the sidebar's part of the toolbar, on the
        // line of the traffic lights and the note title. It stays there when
        // the sidebar collapses, so it is always ONE item: swapping it for a
        // second one in the detail column made the toggle vanish and the new
        // one slide in from above mid-animation.
        .toolbar {
            SidebarToggleItem(placement: .automatic)
        }
        .background(
            SidebarSplitHook(workspaceKey: store.workspaceURL?.path,
                             contentWidth: { longestRowWidth() },
                             onCollapsedChange: { collapsed in
                                 // Dragging past the minimum collapses the column
                                 // without going through our binding; mirror it so
                                 // the toolbar shows the way back.
                                 let target: NavigationSplitViewVisibility = collapsed ? .detailOnly : .all
                                 if appModel.columnVisibility != target { appModel.columnVisibility = target }
                             })
                .frame(width: 0, height: 0)
        )
        .onChange(of: appModel.selectedNoteId, initial: true) { _, id in
            revealSelectedNote(id)
        }
        // A note opened from elsewhere (search, New Note) unfolds the
        // library so its row shows; a folded library stays folded at launch.
        .onChange(of: appModel.selectedNoteId) { _, id in
            if id != nil, libraryCollapsed { libraryCollapsed = false }
        }
    }

    /// The natural width of the widest note row (indent + file name + chrome),
    /// for double-click-to-fit on the divider.
    private func longestRowWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let outer = Self.leadingInset + 8
        return store.notes.reduce(SidebarWidthPolicy.minimum) { widest, note in
            let depth = CGFloat(note.relativePath.split(separator: "/").count)
            let indent = NoteTreeIndent.base + depth * NoteTreeIndent.perLevel
                + NoteTreeIndent.icon + NoteTreeIndent.iconGap
            let text = (note.filename as NSString).size(withAttributes: [.font: font]).width
            return Swift.max(widest, outer + indent + ceil(text) + 10 + (note.pinned ? 16 : 0))
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSearchField()
                .padding(.leading, Self.leadingInset)
                .padding(.trailing, 8)
                .padding(.top, 4)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    notesSection
                }
                .padding(.leading, Self.leadingInset)
                .padding(.trailing, 8)
                .padding(.bottom, 16)
                .background(SidebarScrollerConfigurator())
            }
            .scrollContentBackground(.hidden)

            SidebarSettingsRow()
                .padding(.leading, Self.leadingInset)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
        }
    }

    // MARK: Notes tree

    @ViewBuilder private var notesSection: some View {
        LibraryHeader(isCollapsed: libraryCollapsed) {
            withAnimation(.easeInOut(duration: 0.15)) { libraryCollapsed.toggle() }
        }

        let tree = NoteTreeBuilder.build(from: sortedNotes)
        if libraryCollapsed {
            EmptyView()
        } else if tree.totalCount == 0 {
            Text("No notes yet")
                .font(.notely(12.5))
                .foregroundColor(.tertiaryText)
                .padding(.leading, NoteTreeIndent.base)
                .frame(height: 28)
        } else {
            NoteFolderContents(folder: tree, depth: 0, expandedFolders: $expandedFolders)
        }
    }

    /// Expands every folder on the way to the selected note so it is visible.
    private func revealSelectedNote(_ id: String?) {
        guard let id, let note = store.notes.first(where: { $0.id == id }) else { return }
        expandedFolders.formUnion(NoteTreeBuilder.ancestorIds(ofRelativePath: note.relativePath))
    }
}

// MARK: - Sorting

enum NoteSorting {
    static func sorted(_ notes: [FileNote], by mode: SortMode) -> [FileNote] {
        notes.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            switch mode {
            case .updatedDesc: return lhs.updatedAt > rhs.updatedAt
            case .createdDesc: return lhs.createdAt > rhs.createdAt
            case .titleAsc: return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            }
        }
    }
}

// MARK: - Library heading and search

/// The open folder's name, heading the notes tree. Clicking it folds the
/// whole library; … opens the folder options (open another folder, new
/// window, reveal, sort); + makes a new note.
private struct LibraryHeader: View {
    /// Whether the library's tree is folded away.
    let isCollapsed: Bool
    let toggle: () -> Void
    @Environment(FileNoteStore.self) var store
    @Environment(AppModel.self) var appModel
    @Environment(\.openWindow) private var openWindow
    @State private var isHovering = false
    @State private var isHoveringMore = false
    @State private var isHoveringAdd = false

    private var name: String {
        store.workspaceURL?.lastPathComponent ?? "Notes"
    }

    var body: some View {
        HStack(spacing: 2) {
            // The name folds and unfolds the library (design board ㉚ C). Its
            // icon turns into the disclosure arrow on hover — and stays an
            // arrow while folded — like the folder rows below.
            Button(action: toggle) {
                HStack(spacing: NoteTreeIndent.iconGap) {
                    Group {
                        if isHovering || isCollapsed {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondaryText)
                        } else {
                            ShiyeIcon(.library, size: NoteTreeIndent.icon)
                                .foregroundColor(.iconMuted)
                        }
                    }
                    .frame(width: NoteTreeIndent.icon, height: NoteTreeIndent.icon)
                    Text(name)
                        .font(.notely(13, weight: .medium))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.leading, NoteTreeIndent.base)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Show Notes" : "Hide Notes")

            Menu {
                Button("Open Folder…") {
                    guard let url = NotesFolderPanel.choose() else { return }
                    store.openWorkspace(at: url)
                    appModel.openNote(nil)
                }
                Button("Open in New Window") { openWindow(id: "main") }
                if let url = store.workspaceURL {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Divider()
                Picker("Sort By", selection: Binding(get: { appModel.sortMode }, set: { appModel.setSortMode($0) })) {
                    ForEach(SortMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } label: {
                ShiyeIcon(.more, size: 15)
                    .foregroundColor(isHoveringMore ? .primaryText : .iconMuted)
                    .frame(width: 24, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isHoveringMore ? Color.cardHover : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Folder Options")
            .accessibilityLabel("Folder Options")
            .onHover { isHoveringMore = $0 }

            Button {
                appModel.openNote(store.createNote()?.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHoveringAdd ? .primaryText : .iconMuted)
                    .frame(width: 24, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isHoveringAdd ? Color.cardHover : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Note (⌘N)")
            .onHover { isHoveringAdd = $0 }
        }
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color.cardHover : Color.clear)
        )
        .onHover { isHovering = $0 }
    }
}

/// Search styled as a plain sidebar row. Clicking it opens the Spotlight-style
/// quick search popover (SearchPopover), which owns the query and the fuzzy
/// matching — the sidebar itself no longer filters inline.
private struct SidebarSearchField: View {
    @Environment(AppModel.self) private var appModel
    @State private var isHovering = false

    var body: some View {
        Button { appModel.presentSearch() } label: {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.iconMuted)
                    .frame(width: 16)
                Text("Search")
                    .font(.notely(13))
                    .foregroundColor(.tertiaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.cardHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isHovering ? Color.controlBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Search Notes (⇧⌘F)")
    }
}

struct ShortcutHint: View {
    let text: String
    var boxed = false

    var body: some View {
        Text(text)
            .font(.notely(11, weight: .medium))
            .foregroundColor(.tertiaryText)
            .padding(.horizontal, boxed ? 5 : 0)
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(boxed ? Color.fromHex("#FAFAF9") : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(boxed ? Color.controlBorder : Color.clear, lineWidth: 1)
            )
    }
}

// MARK: - Rows

struct SidebarSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.notely(11.5, weight: .semibold))
            .foregroundColor(.tertiaryText)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 3)
    }
}

/// A top-level navigation row (icon, title).
/// A sidebar icon: one of 拾页's glyphs, or an SF Symbol for the generic
/// actions (settings, search…).
enum SidebarIcon {
    case glyph(ShiyeGlyph)
    case symbol(String)
}

private struct SidebarIconImage: View {
    let icon: SidebarIcon
    var size: CGFloat = 16
    var symbolFont: Font = .system(size: 13, weight: .regular)

    var body: some View {
        switch icon {
        case .glyph(let glyph):
            ShiyeIcon(glyph, size: size)
        case .symbol(let name):
            Image(systemName: name).font(symbolFont)
        }
    }
}

struct SidebarRow: View {
    let icon: SidebarIcon
    let title: String
    var isSelected = false
    /// Bold text without the selected fill — the row's subtree holds the
    /// selection (the design's "笔记" row while a note is open).
    var isEmphasized = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SidebarIconImage(icon: icon)
                    .foregroundColor(isSelected || isEmphasized ? .primaryText : .iconMuted)
                    .frame(width: 16)
                Text(title)
                    .font(.notely(13, weight: isSelected || isEmphasized ? .semibold : .regular))
                    .foregroundColor(isSelected || isEmphasized ? .primaryText : .secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.groundSelectedBg : (isHovering ? Color.cardHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Tree geometry (design board ⑱ option A): every row leads with a 16pt
/// icon — folder, open folder, or document — and each level indents by one
/// icon plus its gap, so children line up under their parent's name.
enum NoteTreeIndent {
    /// Leading inset of a top-level row's icon.
    static let base: CGFloat = 14
    static let icon: CGFloat = 16
    static let iconGap: CGFloat = 8
    static var perLevel: CGFloat { icon + iconGap }
}

/// Line-drawn folder, closed or open (no open-folder SF Symbol exists).
/// Drawn on a 24-unit grid like the design's SVG.
struct FolderGlyph: Shape {
    var open: Bool

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        if !open {
            path.move(to: p(3, 7))
            path.addQuadCurve(to: p(5, 5), control: p(3, 5))
            path.addLine(to: p(9, 5))
            path.addLine(to: p(11, 7))
            path.addLine(to: p(19, 7))
            path.addQuadCurve(to: p(21, 9), control: p(21, 7))
            path.addLine(to: p(21, 17))
            path.addQuadCurve(to: p(19, 19), control: p(21, 19))
            path.addLine(to: p(5, 19))
            path.addQuadCurve(to: p(3, 17), control: p(3, 19))
            path.closeSubpath()
        } else {
            // Back panel with the tab…
            path.move(to: p(3, 19))
            path.addLine(to: p(3, 7))
            path.addQuadCurve(to: p(5, 5), control: p(3, 5))
            path.addLine(to: p(9, 5))
            path.addLine(to: p(11, 7))
            path.addLine(to: p(18, 7))
            path.addQuadCurve(to: p(20, 9), control: p(20, 7))
            path.addLine(to: p(20, 10))
            // …and the front flap, tilted open.
            path.move(to: p(3, 19))
            path.addLine(to: p(5.6, 11.4))
            path.addQuadCurve(to: p(7.5, 10), control: p(6.1, 10))
            path.addLine(to: p(21, 10))
            path.addLine(to: p(18.6, 17.6))
            path.addQuadCurve(to: p(16.7, 19), control: p(18.2, 19))
            path.closeSubpath()
        }
        return path
    }
}

/// The folders, then the notes, of one folder in the tree.
private struct NoteFolderContents: View {
    let folder: NoteFolder
    let depth: Int
    @Binding var expandedFolders: Set<String>
    var baseIndent: CGFloat = NoteTreeIndent.base

    var body: some View {
        ForEach(folder.folders) { child in
            FolderRow(folder: child, depth: depth, isExpanded: expandedFolders.contains(child.id), baseIndent: baseIndent) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedFolders.contains(child.id) {
                        expandedFolders.remove(child.id)
                    } else {
                        expandedFolders.insert(child.id)
                    }
                }
            }
            if expandedFolders.contains(child.id) {
                NoteFolderContents(folder: child, depth: depth + 1, expandedFolders: $expandedFolders, baseIndent: baseIndent)
            }
        }
        ForEach(folder.notes) { note in
            // Note titles line up with sibling folder names (past the chevron).
            NoteRow(note: note, leading: leading(for: depth))
        }
    }

    private func leading(for depth: Int) -> CGFloat {
        baseIndent + CGFloat(depth) * NoteTreeIndent.perLevel
    }
}

private struct FolderRow: View {
    let folder: NoteFolder
    let depth: Int
    let isExpanded: Bool
    var baseIndent: CGFloat = NoteTreeIndent.base
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: NoteTreeIndent.iconGap) {
                // Hovering swaps the folder for the disclosure arrow, so the
                // arrow never takes up room of its own.
                Group {
                    if isHovering {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondaryText)
                    } else {
                        FolderGlyph(open: isExpanded)
                            .stroke(isExpanded ? Color.secondaryText : Color.iconMuted,
                                    style: StrokeStyle(lineWidth: 1.15, lineJoin: .round))
                    }
                }
                .frame(width: NoteTreeIndent.icon, height: NoteTreeIndent.icon)
                Text(folder.name)
                    .font(.notely(13, weight: isExpanded ? .medium : .regular))
                    .foregroundColor(isExpanded || isHovering ? .primaryText : .secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, baseIndent + CGFloat(depth) * NoteTreeIndent.perLevel)
            .padding(.trailing, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.cardHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// One note in the tree. Carries the note actions that used to live on the
/// note list's cards (pin, rename, reveal, delete).
private struct NoteRow: View {
    let note: FileNote
    /// Leading inset of the row's icon, measured from the sidebar row's edge.
    let leading: CGFloat
    @Environment(FileNoteStore.self) var store
    @Environment(AppModel.self) var appModel
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var renameText = ""

    private var isSelected: Bool {
        appModel.selectedNoteId == note.id && !appModel.showSettings
    }

    /// Rows show the file name (not the first line, which for clipped
    /// articles is just their opening sentence).
    private var displayTitle: String { note.filename }

    var body: some View {
        Button {
            appModel.openNote(note.id)
        } label: {
            HStack(spacing: NoteTreeIndent.iconGap) {
                ShiyeIcon(.note, size: 15)
                    .foregroundColor(isSelected ? .secondaryText : .faintIcon)
                    .frame(width: NoteTreeIndent.icon)
                Text(displayTitle)
                    .font(.notely(13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primaryText : .secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.iconMuted)
                }
            }
            .padding(.leading, leading)
            .padding(.trailing, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.groundSelectedBg : (isHovering ? Color.cardHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(note.pinned ? "Unpin" : "Pin") { store.togglePin(note.id) }
            Button("Rename…") {
                renameText = note.filename
                isRenaming = true
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
            Divider()
            Button("Delete", role: .destructive) {
                if appModel.selectedNoteId == note.id { appModel.selectedNoteId = nil }
                store.deleteNote(note.id)
            }
        }
        .alert("Rename Note", isPresented: $isRenaming) {
            TextField("File name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { performRename() }
        } message: {
            Text("Enter a new file name (without the .md extension).")
        }
    }

    private func performRename() {
        let wasSelected = appModel.selectedNoteId == note.id
        if let newId = store.renameNote(note.id, to: renameText), wasSelected {
            appModel.selectedNoteId = newId
        }
    }
}

// MARK: - Bottom: Settings

private struct SidebarSettingsRow: View {
    @Environment(AppModel.self) var appModel

    var body: some View {
        SidebarRow(icon: .symbol("slider.horizontal.3"), title: "Settings", isSelected: appModel.showSettings) {
            appModel.showSettings.toggle()
        }
    }
}

/// The sidebar button as a toolbar item: a flat icon, without the Liquid
/// Glass circle macOS 26 puts behind toolbar buttons.
struct SidebarToggleItem: ToolbarContent {
    let placement: ToolbarItemPlacement

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: placement) { SidebarToggleButton() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { SidebarToggleButton() }
        }
    }
}

/// Shows / hides the sidebar; stands in for the system toggle (see
/// AppShellView for why that one is removed).
struct SidebarToggleButton: View {
    @Environment(AppModel.self) var appModel

    var body: some View {
        Button {
            appModel.toggleSidebar()
        } label: {
            Label {
                Text(appModel.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            } icon: {
                Image(nsImage: ShiyeGlyph.sidebar.templateImage())
            }
        }
        .help(appModel.isSidebarVisible ? "Hide Sidebar (⌥⌘S)" : "Show Sidebar (⌥⌘S)")
    }
}

/// Hooks the split view hosting the sidebar to add the ⑰ behaviors the
/// SwiftUI column API lacks: snap on release, haptic ticks at snap points,
/// double-click the divider to fit / reset, and a remembered width per
/// workspace. (Dragging past the minimum to collapse is the split view's own.)
private struct SidebarSplitHook: NSViewRepresentable {
    let workspaceKey: String?
    let contentWidth: () -> CGFloat
    let onCollapsedChange: (Bool) -> Void

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.contentWidth = contentWidth
        view.onCollapsedChange = onCollapsedChange
        view.workspaceKey = workspaceKey
        return view
    }

    func updateNSView(_ view: HookView, context: Context) {
        view.contentWidth = contentWidth
        view.onCollapsedChange = onCollapsedChange
        view.workspaceKey = workspaceKey
    }

    final class HookView: NSView {
        var contentWidth: () -> CGFloat = { SidebarWidthPolicy.standardDefault }
        var onCollapsedChange: (Bool) -> Void = { _ in }
        var workspaceKey: String? {
            didSet { if workspaceKey != oldValue { restoreSavedWidth() } }
        }

        private weak var splitView: NSSplitView?
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var isDraggingDivider = false
        private var lastWidth: CGFloat = 0
        private var wasCollapsed = false

        deinit { detach() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            var view: NSView? = superview
            while let current = view, !(current is NSSplitView) { view = current.superview }
            guard let split = view as? NSSplitView else { return }
            splitView = split
            lastWidth = sidebarWidth
            enforceMinimum()
            removeTitlebarSeparators()

            observers.append(NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main) { [weak self] _ in
                    self?.didResize()
                })
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                self?.handle(event) ?? event
            }
            restoreSavedWidth()
        }

        private func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        private var sidebarView: NSView? { splitView?.arrangedSubviews.first }
        private var sidebarWidth: CGFloat { sidebarView?.frame.width ?? 0 }
        private var isCollapsed: Bool {
            guard let split = splitView, let sidebar = sidebarView else { return true }
            return split.isSubviewCollapsed(sidebar) || sidebar.frame.width < 1
        }

        private func isOnDivider(_ event: NSEvent) -> Bool {
            guard event.window === window, let split = splitView, !isCollapsed else { return false }
            let point = split.convert(event.locationInWindow, from: nil)
            return split.bounds.contains(point) && abs(point.x - sidebarWidth) <= 5
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .leftMouseDown where isOnDivider(event):
                enforceMinimum()
                if event.clickCount == 2 {
                    let target = SidebarWidthPolicy.doubleClickTarget(current: sidebarWidth, contentWidth: contentWidth())
                    setWidth(target, save: true)
                    return nil
                }
                isDraggingDivider = true
            case .leftMouseUp where isDraggingDivider:
                isDraggingDivider = false
                DispatchQueue.main.async { [weak self] in self?.settle() }
            default:
                break
            }
            return event
        }

        private func didResize() {
            if isCollapsed != wasCollapsed {
                wasCollapsed = isCollapsed
                let collapsed = wasCollapsed
                DispatchQueue.main.async { [weak self] in self?.onCollapsedChange(collapsed) }
            }
            let width = sidebarWidth
            if isDraggingDivider, SidebarWidthPolicy.crossedSnapPoint(from: lastWidth, to: width) != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            lastWidth = width
        }

        private func settle() {
            guard !isCollapsed else { return }
            setWidth(SidebarWidthPolicy.settle(sidebarWidth), save: true)
        }

        /// No hard line under the title bar: the title and the page read as
        /// one surface, and text scrolling under the toolbar gets the system's
        /// soft edge instead.
        private func removeTitlebarSeparators() {
            window?.titlebarSeparatorStyle = .none
            (splitView?.delegate as? NSSplitViewController)?.splitViewItems.forEach {
                $0.titlebarSeparatorStyle = .none
            }
        }

        /// Keep the split view item's own minimum just under the narrowest
        /// width (positioning the divider at or under the item's minimum
        /// collapses it), whatever SwiftUI derived from the content.
        private func enforceMinimum() {
            guard let item = (splitView?.delegate as? NSSplitViewController)?.splitViewItems.first else { return }
            let floor = SidebarWidthPolicy.minimum - 8
            if item.minimumThickness != floor { item.minimumThickness = floor }
        }

        private func setWidth(_ width: CGFloat, save: Bool) {
            enforceMinimum()
            guard let split = splitView, !isCollapsed else { return }
            if abs(sidebarWidth - width) > 0.5 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    split.setPosition(width, ofDividerAt: 0)
                    split.layoutSubtreeIfNeeded()
                }
            }
            if save, let key = workspaceKey {
                UserDefaults.standard.set(Double(width), forKey: "notely.sidebarWidth." + key)
            }
        }

        /// The folder's saved width, or the default for a folder opened for
        /// the first time — without one the split view keeps whatever width
        /// it started at (140 after the welcome page).
        private func restoreSavedWidth() {
            guard let key = workspaceKey else { return }
            let saved = UserDefaults.standard.object(forKey: "notely.sidebarWidth." + key) as? Double
            // Widths saved while the icon rail existed (64) count as unset.
            let width = saved.map { CGFloat($0) }.flatMap { $0 >= SidebarWidthPolicy.minimum ? $0 : nil }
                ?? SidebarWidthPolicy.standardDefault
            DispatchQueue.main.async { [weak self] in self?.setWidth(width, save: false) }
        }
    }
}

// MARK: - Scroller

private struct SidebarScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configureScroller(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configureScroller(from: nsView) }
    }

    private func configureScroller(from view: NSView) {
        guard let scrollView = view.enclosingScrollView,
              !(scrollView.verticalScroller is SidebarScroller) else { return }

        let scroller = SidebarScroller(frame: .zero)
        scroller.scrollerStyle = .overlay
        scrollView.verticalScroller = scroller
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
    }
}

private final class SidebarScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 7 }

    override func drawKnob() {
        let slotRect = rect(for: .knobSlot)
        let rawKnobRect = rect(for: .knob)
        let height = max(34, rawKnobRect.height * 0.66)
        let y = rawKnobRect.midY - height / 2
        let knobRect = NSRect(x: slotRect.midX - 2, y: y, width: 4, height: height)

        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: knobRect, xRadius: 2, yRadius: 2).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Keep the sidebar scrollbar quiet: no track, only the lightweight thumb.
    }
}
