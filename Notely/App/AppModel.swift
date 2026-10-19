import Foundation
import Observation
import SwiftUI

@Observable
final class AppModel {
    var selectedNoteId: String? = nil
    /// True while the Spotlight-style quick search popover is open
    /// (⇧⌘F, the sidebar's search row, or the rail's search button).
    var isSearchPresented: Bool = false
    var sortMode: SortMode = SortMode(rawValue: AppSettings.sortMode) ?? .updatedDesc
    var showSettings: Bool = false
    /// The Memos page is showing in place of the editor (design board ㉛).
    var showMemos: Bool = false
    /// An image, video or PDF from the sidebar is showing in place of the
    /// editor (its path, a `LibraryFile` id).
    var selectedFileId: String? = nil
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

    func openNote(_ id: String?) {
        showSettings = false
        showMemos = false
        selectedFileId = nil
        selectedNoteId = id
        isSearchPresented = false
    }

    func openMemos() {
        showSettings = false
        isSearchPresented = false
        selectedNoteId = nil
        selectedFileId = nil
        showMemos = true
    }

    func openFile(_ id: String) {
        showSettings = false
        showMemos = false
        isSearchPresented = false
        selectedNoteId = nil
        selectedFileId = id
    }

    func presentSearch() { isSearchPresented = true }

    func dismissSearch() { isSearchPresented = false }
}
