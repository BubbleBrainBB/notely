import SwiftUI
import AppKit

/// Left column, after the 拾页 sidebar comp: workspace switcher, New Note,
/// search, then the notes tree (workspace folders as notebooks), with
/// Settings pinned to the bottom.
struct SidebarView: View {
    @Environment(AppModel.self) var appModel
    @Environment(FileNoteStore.self) var store
    @State private var notesExpanded = true
    @State private var expandedFolders: Set<String> = []
    @FocusState private var searchFocused: Bool

    /// Matches the trailing 8. (Was 22 while the hidden-title-bar window
    /// clipped ~14pt off the column's leading edge; the unified toolbar
    /// window doesn't.)
    static let leadingInset: CGFloat = 8

    private var isSearching: Bool {
        !appModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sortedNotes: [FileNote] {
        NoteSorting.sorted(store.notes, by: appModel.sortMode)
    }

    @State private var width: CGFloat = SidebarWidthPolicy.standardDefault

    private var tier: SidebarTier { SidebarTier(width: width) }

    var body: some View {
        Group {
            if tier == .rail {
                SidebarRail(sortedNotes: sortedNotes, expandedFolders: $expandedFolders)
            } else {
                list
            }
        }
        // Fully compressible: SwiftUI derives the column's minimum from the
        // content's, and the standard list's fixed rows (~140pt) would
        // otherwise become a floor the 64pt rail can't get under.
        .frame(minWidth: 0, maxWidth: .infinity)
        .environment(\.sidebarTier, tier)
        .animation(.easeInOut(duration: 0.2), value: tier)
        .background(Color.sidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.borderColor).frame(width: 1)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            width = newWidth
        }
        .background(
            SidebarSplitHook(workspaceKey: store.workspaceURL?.path,
                             contentWidth: { longestRowWidth() },
                             onCollapsedChange: { collapsed in
                                 // Dragging past the minimum collapses the column
                                 // without going through our binding; mirror it so
                                 // the rail stops hiding the system toggle.
                                 let target: NavigationSplitViewVisibility = collapsed ? .detailOnly : .all
                                 if appModel.columnVisibility != target { appModel.columnVisibility = target }
                             })
                .frame(width: 0, height: 0)
        )
        .onReceive(NotificationCenter.default.publisher(for: .focusNoteSearch)) { _ in
            searchFocused = true
        }
        .onChange(of: appModel.selectedNoteId, initial: true) { _, id in
            revealSelectedNote(id)
        }
    }

    /// The natural width of the widest note row (indent + file name + chrome),
    /// for double-click-to-fit on the divider.
    private func longestRowWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let outer = Self.leadingInset + 8
        return store.notes.reduce(SidebarWidthPolicy.standardMin) { widest, note in
            let depth = CGFloat(note.relativePath.split(separator: "/").count)
            let indent = NoteTreeIndent.base + depth * NoteTreeIndent.perLevel
                + NoteTreeIndent.icon + NoteTreeIndent.iconGap
            let text = (note.filename as NSString).size(withAttributes: [.font: font]).width
            return Swift.max(widest, outer + indent + ceil(text) + 10 + (note.pinned ? 16 : 0))
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    WorkspaceMenu()
                    HideSidebarButton()
                }
                .padding(.bottom, 8)
                NewNoteButton()
                SidebarSearchField(text: Bindable(appModel).searchText, isFocused: $searchFocused)
            }
            .padding(.leading, Self.leadingInset)
            .padding(.trailing, 8)
            .padding(.top, 4)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if isSearching {
                        searchResults
                    } else {
                        notesSection
                    }
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
        SidebarSectionLabel(title: "Library")

        SidebarRow(
            icon: "books.vertical",
            title: "Notes",
            count: store.notes.count,
            isEmphasized: appModel.selectedNoteId != nil && !appModel.showSettings
        ) {
            withAnimation(.easeInOut(duration: 0.15)) { notesExpanded.toggle() }
        }
        .contextMenu {
            Picker("Sort By", selection: Binding(get: { appModel.sortMode }, set: { appModel.setSortMode($0) })) {
                ForEach(SortMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        }

        if notesExpanded {
            let tree = NoteTreeBuilder.build(from: sortedNotes)
            if tree.totalCount == 0 {
                Text("No notes yet")
                    .font(.notely(12.5))
                    .foregroundColor(.tertiaryText)
                    .padding(.leading, NoteTreeIndent.base)
                    .frame(height: 28)
            } else {
                NoteFolderContents(folder: tree, depth: 0, expandedFolders: $expandedFolders)
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        let results = NoteSearch.filter(sortedNotes, query: appModel.searchText)
        SidebarSectionLabel(title: results.isEmpty ? "No matching notes" : "\(results.count) results")
        ForEach(results) { note in
            NoteRow(note: note, leading: NoteTreeIndent.base, showsFolder: true)
        }
    }

    /// Expands every folder on the way to the selected note so it is visible.
    private func revealSelectedNote(_ id: String?) {
        guard let id, let note = store.notes.first(where: { $0.id == id }) else { return }
        expandedFolders.formUnion(NoteTreeBuilder.ancestorIds(ofRelativePath: note.relativePath))
        notesExpanded = true
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

// MARK: - Top: workspace, New Note, search

/// The workspace switcher: the open folder's name under a monogram badge.
private struct WorkspaceMenu: View {
    @Environment(FileNoteStore.self) var store
    @Environment(AppModel.self) var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.sidebarTier) private var tier

    private var name: String {
        store.workspaceURL?.lastPathComponent ?? "Notes"
    }

    var body: some View {
        Menu {
            Button("Open Folder…") {
                guard let url = NotesFolderPanel.choose() else { return }
                store.openWorkspace(at: url)
                appModel.openNote(nil)
            }
            Button("Open in New Window") { openWindow(id: "main") }
            if let url = store.workspaceURL {
                Divider()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        } label: {
            HStack(spacing: 9) {
                Text(String(name.prefix(1)).uppercased())
                    .font(.notely(12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primaryText))
                Text(name)
                    .font(.notely(13, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.iconMuted)
                Spacer(minLength: 0)
                if tier == .wide {
                    Text(store.notes.count == 1 ? "1 note" : "\(store.notes.count) notes")
                        .font(.notely(11))
                        .foregroundColor(.tertiaryText)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// The raised primary action at the top of the sidebar.
private struct NewNoteButton: View {
    @Environment(FileNoteStore.self) var store
    @Environment(AppModel.self) var appModel
    @State private var isHovering = false

    var body: some View {
        Button {
            appModel.openNote(store.createNote()?.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)
                Text("New Note")
                    .font(.notely(13, weight: .semibold))
                Spacer(minLength: 0)
                ShortcutHint(text: "⌘N", boxed: true)
            }
            .foregroundColor(.primaryText)
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.fromHex("#FBFBFA") : Color.surface)
                    .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.controlBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Search styled as a plain sidebar row; the field is live, not a button.
private struct SidebarSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.iconMuted)
                .frame(width: 16)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.notely(13))
                .foregroundColor(.primaryText)
                .focused(isFocused)
                .onExitCommand { text = ""; isFocused.wrappedValue = false }
            if text.isEmpty {
                ShortcutHint(text: "⇧⌘F")
            } else {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.iconMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isFocused.wrappedValue ? Color.surface : (isHovering ? Color.cardHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isFocused.wrappedValue ? Color.controlBorder : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
        .onHover { isHovering = $0 }
    }
}

private struct ShortcutHint: View {
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

/// A top-level navigation row (icon, title, trailing count).
struct SidebarRow: View {
    let icon: String
    let title: String
    var count: Int? = nil
    var isSelected = false
    /// Bold text without the selected fill — the row's subtree holds the
    /// selection (the design's "笔记" row while a note is open).
    var isEmphasized = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isSelected || isEmphasized ? .primaryText : .iconMuted)
                    .frame(width: 16)
                Text(title)
                    .font(.notely(13, weight: isSelected || isEmphasized ? .semibold : .regular))
                    .foregroundColor(isSelected || isEmphasized ? .primaryText : .secondaryText)
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)")
                        .font(.notely(12))
                        .foregroundColor(.tertiaryText)
                }
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
    @Environment(\.sidebarTier) private var tier
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
                Text(tier == .wide ? (folder.totalCount == 1 ? "1 note" : "\(folder.totalCount) notes") : "\(folder.totalCount)")
                    .font(.notely(11.5))
                    .foregroundColor(.faintText)
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

/// One note in the tree or in search results. Carries the note actions that
/// used to live on the note list's cards (pin, rename, reveal, delete).
private struct NoteRow: View {
    let note: FileNote
    /// Leading inset of the row's icon, measured from the sidebar row's edge.
    let leading: CGFloat
    var showsFolder = false
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
                Image(systemName: "doc")
                    .font(.system(size: 11.5))
                    .foregroundColor(isSelected ? .secondaryText : .faintIcon)
                    .frame(width: NoteTreeIndent.icon)
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayTitle)
                        .font(.notely(13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primaryText : .secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if showsFolder && note.relativePath != "/" {
                        Text(note.relativePath.dropFirst())
                            .font(.notely(11))
                            .foregroundColor(.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.iconMuted)
                }
            }
            .padding(.leading, leading)
            .padding(.trailing, 10)
            .frame(minHeight: 28)
            .padding(.vertical, showsFolder && note.relativePath != "/" ? 3 : 0)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.selectedBg : (isHovering ? Color.cardHover : Color.clear))
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
        SidebarRow(icon: "slider.horizontal.3", title: "Settings", isSelected: appModel.showSettings) {
            appModel.showSettings.toggle()
        }
    }
}

// MARK: - Width tiers (design board ⑰)

private struct SidebarTierKey: EnvironmentKey {
    static let defaultValue: SidebarTier = .standard
}

extension EnvironmentValues {
    var sidebarTier: SidebarTier {
        get { self[SidebarTierKey.self] }
        set { self[SidebarTierKey.self] = newValue }
    }
}

extension Notification.Name {
    /// Asks the sidebar to resize itself; userInfo["width"] = CGFloat.
    static let sidebarRequestWidth = Notification.Name("notely.sidebarRequestWidth")
}

/// The narrow tier: icons only. Hovering Notes opens the notes tree in a
/// flyout so switching notes doesn't need the full sidebar.
private struct SidebarRail: View {
    let sortedNotes: [FileNote]
    @Binding var expandedFolders: Set<String>
    @Environment(AppModel.self) var appModel
    @Environment(FileNoteStore.self) var store
    @State private var showsFlyout = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            RailButton(systemName: "chevron.right.2", help: "Expand Sidebar") {
                NotificationCenter.default.post(name: .sidebarRequestWidth, object: nil,
                                                userInfo: ["width": SidebarWidthPolicy.standardDefault])
            }
            WorkspaceBadgeMenu()
            RailButton(systemName: "plus", help: "New Note (⌘N)", raised: true) {
                appModel.openNote(store.createNote()?.id)
            }
            RailButton(systemName: "magnifyingglass", help: "Search (⇧⌘F)") {
                NotificationCenter.default.post(name: .sidebarRequestWidth, object: nil,
                                                userInfo: ["width": SidebarWidthPolicy.standardDefault])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    NotificationCenter.default.post(name: .focusNoteSearch, object: nil)
                }
            }
            Rectangle().fill(Color.borderColor).frame(width: 28, height: 1)
            RailButton(systemName: "doc.text", help: "Notes",
                       isSelected: appModel.selectedNoteId != nil && !appModel.showSettings) {
                showsFlyout.toggle()
            }
            .onHover { hovering in
                hoverTask?.cancel()
                guard hovering else { return }
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    if !Task.isCancelled { showsFlyout = true }
                }
            }
            .popover(isPresented: $showsFlyout, arrowEdge: .trailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        SidebarSectionLabel(title: "Notes · \(store.notes.count)")
                        NoteFolderContents(folder: NoteTreeBuilder.build(from: sortedNotes), depth: 0,
                                           expandedFolders: $expandedFolders, baseIndent: 10)
                    }
                    .padding(8)
                }
                .frame(width: 280)
                .frame(maxHeight: 480)
                .environment(\.sidebarTier, .standard)
                // A plain white card as in ⑰, not the system popover material.
                .presentationBackground(Color.surface)
                .environment(\.colorScheme, .light)
            }
            Spacer(minLength: 0)
            RailButton(systemName: "slider.horizontal.3", help: "Settings", isSelected: appModel.showSettings) {
                appModel.showSettings.toggle()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .onChange(of: appModel.selectedNoteId) { _, _ in showsFlyout = false }
    }
}

private struct RailButton: View {
    let systemName: String
    let help: String
    var raised = false
    var isSelected = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: raised ? .semibold : .regular))
                .foregroundColor(isSelected || raised ? .primaryText : .iconMuted)
                .frame(width: 40, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: raised ? 9 : 8, style: .continuous)
                        .fill(raised ? Color.surface : (isSelected ? Color.selectedBg : (isHovering ? Color.cardHover : Color.clear)))
                        .shadow(color: .black.opacity(raised ? 0.05 : 0), radius: 1, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(raised ? Color.controlBorder : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

/// Hide button inside the sidebar (standard / wide tiers), at the end of
/// the workspace row — see AppShellView for why it isn't in the toolbar.
private struct HideSidebarButton: View {
    @Environment(AppModel.self) var appModel
    @State private var isHovering = false

    var body: some View {
        Button {
            appModel.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14))
                .foregroundColor(isHovering ? .primaryText : .iconMuted)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color.cardHover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide Sidebar (⌥⌘S)")
        .onHover { isHovering = $0 }
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
            Label(appModel.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left")
        }
        .help(appModel.isSidebarVisible ? "Hide Sidebar (⌥⌘S)" : "Show Sidebar (⌥⌘S)")
    }
}

/// The workspace monogram alone, keeping the switcher menu.
private struct WorkspaceBadgeMenu: View {
    @Environment(FileNoteStore.self) var store
    @Environment(AppModel.self) var appModel

    private var name: String { store.workspaceURL?.lastPathComponent ?? "Notes" }

    var body: some View {
        Menu {
            Text(name)
            Button("Open Folder…") {
                guard let url = NotesFolderPanel.choose() else { return }
                store.openWorkspace(at: url)
                appModel.openNote(nil)
            }
        } label: {
            Text(String(name.prefix(1)).uppercased())
                .font(.notely(13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primaryText))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(name)
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
            enforceRailMinimum()

            observers.append(NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main) { [weak self] _ in
                    self?.didResize()
                })
            observers.append(NotificationCenter.default.addObserver(
                forName: .sidebarRequestWidth, object: nil, queue: .main) { [weak self] note in
                    guard let self, self.window?.isKeyWindow == true,
                          let width = note.userInfo?["width"] as? CGFloat else { return }
                    self.setWidth(width, save: true)
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
                enforceRailMinimum()
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

        /// Belt and braces for the rail: make sure the split view item's own
        /// minimum is below 64 (positioning the divider at or under the
        /// item's minimum collapses it). The content is compressible (see
        /// SidebarView.body), so SwiftUI shouldn't raise it again.
        private func enforceRailMinimum() {
            guard let item = (splitView?.delegate as? NSSplitViewController)?.splitViewItems.first else { return }
            let floor = SidebarWidthPolicy.rail - 8
            if item.minimumThickness != floor { item.minimumThickness = floor }
        }

        private func setWidth(_ width: CGFloat, save: Bool) {
            enforceRailMinimum()
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

        private func restoreSavedWidth() {
            guard let key = workspaceKey,
                  let saved = UserDefaults.standard.object(forKey: "notely.sidebarWidth." + key) as? Double else { return }
            DispatchQueue.main.async { [weak self] in self?.setWidth(CGFloat(saved), save: false) }
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
