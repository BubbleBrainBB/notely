import SwiftUI

struct AppShellView: View {
    @Environment(AppModel.self) var appModel
    @Environment(FileNoteStore.self) var store
    @AppStorage("notely.editorWidth") private var editorWidth: String = "medium"

    static let sidebarWidth: CGFloat = 240

    /// Minimum width for the editor detail column: the capped text column plus
    /// its side insets. Enforced as the detail column's min and folded into the
    /// window min width so the text column never reflows when the sidebar
    /// collapses/expands — the pane stays at or above the cap engagement point.
    private var detailMinWidth: CGFloat {
        WysiwygTextView.columnWidth(for: editorWidth) + WysiwygTextView.minSideInset * 2
    }

    var body: some View {
        @Bindable var appModel = appModel
        if !store.isOpen {
            FolderOpenView()
        } else {
            NavigationSplitView(columnVisibility: $appModel.columnVisibility) {
                SidebarView()
                    // Draggable from the icon rail (64) to 420; opens at 240.
                    // Snapping and tiers: SidebarWidthPolicy / SidebarSplitHook.
                    // The minimum sits a little under the rail: positioning the
                    // divider exactly at the minimum makes the split view collapse.
                    .navigationSplitViewColumnWidth(min: SidebarWidthPolicy.rail - 8, ideal: Self.sidebarWidth,
                                                    max: SidebarWidthPolicy.max)
                    // Any toolbar item beside the traffic lights (the system
                    // toggle, or one at the detail's leading edge) puts a
                    // ~140pt floor under the column, so the 64pt rail couldn't
                    // exist. While the sidebar shows, its hide button lives in
                    // the sidebar itself; the toolbar gets one only when collapsed.
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                Group {
                    if appModel.showSettings {
                        HStack(spacing: 0) {
                            SettingsTabBar()
                            Rectangle().fill(Color.borderColor).frame(width: 1)
                            SettingsContent()
                        }
                        .navigationTitle("Settings")
                    } else {
                        // Extends under the toolbar so text scrolls beneath its
                        // glass; the scroll view insets its content to match.
                        EditorContainerView()
                            .ignoresSafeArea(.container, edges: .top)
                    }
                }
                .navigationSplitViewColumnWidth(min: detailMinWidth, ideal: detailMinWidth, max: .infinity)
                .toolbar {
                    // Collapsed: the way back sits beside the traffic lights.
                    if !appModel.isSidebarVisible {
                        ToolbarItem(placement: .navigation) { SidebarToggleButton() }
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: Self.sidebarWidth + detailMinWidth, minHeight: 600)

        }
    }
}
