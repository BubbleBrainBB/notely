import Foundation
import Observation
import SwiftUI

@Observable
final class AppModel {
    /// The window's open pages, in strip order, pinned ones first (design
    /// board ㊴ B). Never empty: the last one closed leaves a blank draft.
    private(set) var tabs: [NoteTab]
    private(set) var activeTabId: UUID
    /// Closed tabs, newest last, for Reopen Closed Tab (⇧⌘T).
    @ObservationIgnored private var closedTabs: [NoteTab] = []

    init() {
        let first = NoteTab(content: .draft)
        tabs = [first]
        activeTabId = first.id
    }

    /// The detail column's width, set by the shell; the tab strip spans it.
    var pageWidth: CGFloat = 800

    /// The page's width less the toolbar's trailing icons (New Note, Info,
    /// More — the same as with one page, so none overflows into ») — and the
    /// traffic lights and sidebar toggle when the sidebar is hidden.
    var tabStripWidth: CGFloat {
        pageWidth - 164 - (isSidebarVisible ? 0 : 132)
    }

    var activeIndex: Int { tabs.firstIndex { $0.id == activeTabId } ?? 0 }
    var activeTab: NoteTab { tabs[activeIndex] }

    /// What the active tab shows.
    private var activeContent: NoteTab.Content {
        get { activeTab.content }
        set { tabs[activeIndex].content = newValue }
    }

    /// The note in the active tab. Setting nil turns it into a blank draft.
    var selectedNoteId: String? {
        get { if case .note(let id) = activeContent { id } else { nil } }
        set {
            if let newValue {
                activeContent = .note(newValue)
            } else if case .note = activeContent {
                activeContent = .draft
            }
        }
    }

    /// True while the Spotlight-style quick search popover is open
    /// (⇧⌘F, the sidebar's search row, or the rail's search button).
    var isSearchPresented: Bool = false
    var sortMode: SortMode = SortMode(rawValue: AppSettings.sortMode) ?? .updatedDesc
    var showSettings: Bool = false
    /// The Memos page is showing in place of the editor (design board ㉛).
    var showMemos: Bool {
        get { activeContent == .memos }
        set {
            if newValue {
                activeContent = .memos
            } else if activeContent == .memos {
                activeContent = .draft
            }
        }
    }
    /// An image, video or PDF from the sidebar is showing in place of the
    /// editor (its path, a `LibraryFile` id).
    var selectedFileId: String? {
        get { if case .file(let id) = activeContent { id } else { nil } }
        set {
            if let newValue {
                activeContent = .file(newValue)
            } else if case .file = activeContent {
                activeContent = .draft
            }
        }
    }
    /// Bound to the split view, so the system sidebar toggle in the window
    /// toolbar and the ⌥⌘S / ⇧⌘F commands share one source of truth.
    var columnVisibility: NavigationSplitViewVisibility = .all

    var isSidebarVisible: Bool { columnVisibility != .detailOnly }

    /// False while a library opened from the welcome page is handing over to
    /// the main window: the shell starts as one plain white sheet — like the
    /// welcome page — and `revealFrame()` animates it into the window ground
    /// with the page settling into its frame.
    private(set) var frameRevealed = true

    /// The window ground: plain white during the welcome hand-over.
    var groundColor: Color { frameRevealed ? .groundFill : .editorBg }

    /// Call right before opening a library from the welcome page.
    func beginFrameIntro() {
        frameRevealed = false
    }

    func revealFrame() {
        guard !frameRevealed else { return }
        withAnimation(.easeInOut(duration: 0.5)) { frameRevealed = true }
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            columnVisibility = isSidebarVisible ? .detailOnly : .all
        }
    }

    func setSortMode(_ mode: SortMode) {
        sortMode = mode
        AppSettings.sortMode = mode.rawValue
    }

    /// Opens a note: in the tab that already shows it, else in the active
    /// tab — or a new one, with `inNewTab` (⌘-click) or when the active tab
    /// is pinned. `nil` turns the active tab into a blank draft.
    func openNote(_ id: String?, inNewTab: Bool = false) {
        guard let id else {
            dismissOverlays()
            activeContent = .draft
            return
        }
        open(.note(id), inNewTab: inNewTab)
    }

    func openMemos(inNewTab: Bool = false) {
        open(.memos, inNewTab: inNewTab)
    }

    func openFile(_ id: String, inNewTab: Bool = false) {
        open(.file(id), inNewTab: inNewTab)
    }

    private func open(_ content: NoteTab.Content, inNewTab: Bool) {
        dismissOverlays()
        if let existing = tabs.first(where: { $0.content == content }) {
            activeTabId = existing.id
        } else if inNewTab || activeTab.isPinned {
            insertTab(NoteTab(content: content))
        } else {
            activeContent = content
        }
    }

    private func dismissOverlays() {
        showSettings = false
        isSearchPresented = false
    }

    // MARK: - Tabs

    /// The tab strip shows once more than one page is open; with one, the
    /// toolbar keeps the plain title.
    var showsTabStrip: Bool { tabs.count > 1 }

    /// New Tab, New Note and the strip's + are one thing: a blank draft in
    /// a new tab. The active tab already being blank, it stays put.
    func newTab() {
        dismissOverlays()
        guard activeContent != .draft else { return }
        insertTab(NoteTab(content: .draft))
    }

    /// Right after the active tab, but never among the pinned ones.
    private func insertTab(_ tab: NoteTab) {
        let firstUnpinned = tabs.firstIndex { !$0.isPinned } ?? tabs.count
        tabs.insert(tab, at: max(activeIndex + 1, firstUnpinned))
        activeTabId = tab.id
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        dismissOverlays()
        activeTabId = id
    }

    /// ⌘1…⌘8 pick that tab, ⌘9 always the last.
    func selectTab(number: Int) {
        guard !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        selectTab(tabs[index].id)
    }

    /// The next (or previous, with -1) tab, wrapping around.
    func selectTab(offset: Int) {
        guard tabs.count > 1 else { return }
        let index = (activeIndex + offset + tabs.count) % tabs.count
        selectTab(tabs[index].id)
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        if tab.content != .draft {
            closedTabs.append(tab)
            if closedTabs.count > 30 { closedTabs.removeFirst() }
        }
        if tabs.isEmpty {
            let blank = NoteTab(content: .draft)
            tabs = [blank]
            activeTabId = blank.id
        } else if id == activeTabId {
            // Focus goes to the tab on the right, else the one on the left.
            activeTabId = tabs[min(index, tabs.count - 1)].id
        }
    }

    /// ⌘W: closes the active tab. False when it is the window's only one,
    /// so ⌘W closes the window as before. A pinned tab isn't closed: the
    /// first unpinned one comes forward instead.
    func closeActiveTab() -> Bool {
        guard tabs.count > 1 else { return false }
        if activeTab.isPinned {
            if let other = tabs.first(where: { !$0.isPinned }) {
                selectTab(other.id)
            } else {
                newTab()
            }
            return true
        }
        closeTab(activeTabId)
        return true
    }

    func closeOtherTabs(_ id: UUID) {
        for tab in tabs where tab.id != id && !tab.isPinned { closeTab(tab.id) }
        selectTab(id)
    }

    func closeTabsToTheRight(of id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        for tab in tabs[(index + 1)...] where !tab.isPinned { closeTab(tab.id) }
    }

    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    /// ⇧⌘T: the last closed tab, back in a new tab. `exists` drops ones
    /// whose note or file is gone.
    func reopenClosedTab(exists: (NoteTab.Content) -> Bool) {
        while let tab = closedTabs.popLast() {
            guard exists(tab.content) else { continue }
            open(tab.content, inNewTab: true)
            if tab.isPinned { togglePin(activeTabId) }
            return
        }
    }

    func togglePin(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        var tab = tabs.remove(at: index)
        tab.isPinned.toggle()
        // Pinned tabs gather at the leading end, in the order pinned.
        let pinnedCount = tabs.filter(\.isPinned).count
        tabs.insert(tab, at: pinnedCount)
    }

    /// Drag to reorder: moves the tab to `index`, kept on its own side of
    /// the pinned / unpinned boundary.
    func moveTab(_ id: UUID, to index: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: from)
        let pinnedCount = tabs.filter(\.isPinned).count
        let range = tab.isPinned ? 0...pinnedCount : pinnedCount...tabs.count
        tabs.insert(tab, at: min(max(index, range.lowerBound), range.upperBound))
    }

    /// A note or folder moved or renamed in the app: every tab inside it
    /// follows to the new path.
    func remapTabs(from old: String, to new: String) {
        for i in tabs.indices {
            switch tabs[i].content {
            case .note(let id):
                if let moved = LibraryMove.remap(id, from: old, to: new) { tabs[i].content = .note(moved) }
            case .file(let id):
                if let moved = LibraryMove.remap(id, from: old, to: new) { tabs[i].content = .file(moved) }
            case .draft, .memos:
                break
            }
        }
    }

    /// A note or file was deleted: its tabs close; the window's only tab
    /// turns into a blank draft.
    func removeTabs(showing content: NoteTab.Content) {
        for tab in tabs where tab.content == content {
            if tabs.count == 1 {
                tabs[0].content = .draft
            } else if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
                tabs.remove(at: index)
                if tab.id == activeTabId { activeTabId = tabs[min(index, tabs.count - 1)].id }
            }
        }
    }

    /// The library changed on disk: tabs whose note or file no longer
    /// exists close.
    func pruneTabs(keeping exists: (NoteTab.Content) -> Bool) {
        for tab in tabs where !exists(tab.content) {
            removeTabs(showing: tab.content)
        }
    }

    /// A draft written to disk for the first time becomes that note, in the
    /// tab it was typed in — which may no longer be the active one.
    func adoptDraft(_ noteId: String, inTab tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }), tabs[index].content == .draft else { return }
        tabs[index].content = .note(noteId)
    }

    // MARK: - Keeping tabs between launches

    /// Brings back the tabs last open in `workspace`. With none saved, tabs
    /// from another library close; a draft, Memos and anything already
    /// opened inside the new folder stay.
    func restoreTabs(workspace: String) {
        tabsWorkspace = workspace
        if let saved = SavedTabs.load(workspace: workspace) {
            tabs = saved.tabs
            activeTabId = saved.tabs[saved.active].id
            closedTabs = []
            return
        }
        let prefix = workspace.hasSuffix("/") ? workspace : workspace + "/"
        let kept = tabs.filter { $0.content.path.map { $0.hasPrefix(prefix) } ?? true }
        tabs = kept.isEmpty ? [NoteTab(content: .draft)] : kept
        if !tabs.contains(where: { $0.id == activeTabId }) { activeTabId = tabs[0].id }
        closedTabs = []
    }

    /// The library the tabs belong to. Tabs changed while another folder is
    /// opening aren't saved under the new one.
    @ObservationIgnored private var tabsWorkspace: String?

    func saveTabs(workspace: String) {
        guard workspace == tabsWorkspace else { return }
        SavedTabs.save(tabs, active: activeIndex, workspace: workspace)
    }

    func presentSearch() { isSearchPresented = true }

    func dismissSearch() { isSearchPresented = false }
}
