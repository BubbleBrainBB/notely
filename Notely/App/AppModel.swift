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
    /// Bound to the split view, so the system sidebar toggle in the window
    /// toolbar and the ⌥⌘S / ⇧⌘F commands share one source of truth.
    var columnVisibility: NavigationSplitViewVisibility = .all

    var isSidebarVisible: Bool { columnVisibility != .detailOnly }

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
        selectedNoteId = id
        isSearchPresented = false
    }

    func presentSearch() { isSearchPresented = true }

    func dismissSearch() { isSearchPresented = false }
}
