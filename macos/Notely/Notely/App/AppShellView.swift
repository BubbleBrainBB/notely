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
            ZStack(alignment: .top) {
                NavigationSplitView(columnVisibility: $appModel.columnVisibility) {
                    SidebarView()
                        // Draggable from 200 to 420; opens at 240; dragging
                        // narrower collapses it. Snapping: SidebarWidthPolicy /
                        // SidebarSplitHook. The minimum sits a little under 200:
                        // positioning the divider exactly at the minimum makes the
                        // split view collapse.
                        .navigationSplitViewColumnWidth(min: SidebarWidthPolicy.minimum - 8, ideal: Self.sidebarWidth,
                                                        max: SidebarWidthPolicy.max)
                        // Our own toggle instead (SidebarView adds it while the
                        // sidebar shows, the detail while it is collapsed).
                        .toolbar(removing: .sidebarToggle)
                } detail: {
                    // Extends under the toolbar so text scrolls beneath its
                    // glass; the scroll view insets its content to match.
                    EditorContainerView()
                        .ignoresSafeArea(.container, edges: .top)
                        // No toolbar band or line over the page: the title sits
                        // on the same white as the text, and text scrolling up
                        // fades out under it instead of meeting a hard edge.
                        .toolbarBackground(.hidden, for: .windowToolbar)
                        .overlay(alignment: .top) {
                            LinearGradient(
                                stops: [
                                    .init(color: Color.editorBg, location: 0),
                                    .init(color: Color.editorBg, location: 0.55),
                                    .init(color: Color.editorBg.opacity(0), location: 1),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 76)
                            .allowsHitTesting(false)
                            .ignoresSafeArea(.container, edges: .top)
                        }
                    .navigationSplitViewColumnWidth(min: detailMinWidth, ideal: detailMinWidth, max: .infinity)
                    .toolbar {
                        // Collapsed: the way back sits beside the traffic lights.
                        if !appModel.isSidebarVisible {
                            SidebarToggleItem(placement: .navigation)
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
                .frame(minWidth: Self.sidebarWidth + detailMinWidth, minHeight: 600)

                // Spotlight-style quick search, floating over the window.
                if appModel.isSearchPresented {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { appModel.dismissSearch() }
                        .transition(.opacity)
                    SearchPopover()
                        .padding(.top, 92)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }

                // Settings: a card over the dimmed window (design board ㉑ B).
                if appModel.showSettings {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture { appModel.showSettings = false }
                        .transition(.opacity)
                    SettingsModal()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .animation(.easeOut(duration: 0.16), value: appModel.isSearchPresented)
            .animation(.easeOut(duration: 0.16), value: appModel.showSettings)
        }
    }
}
