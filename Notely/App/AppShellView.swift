import SwiftUI

struct AppShellView: View {
    @Environment(AppModel.self) var appModel
    @Environment(FileNoteStore.self) var store
    @AppStorage("notely.editorWidth") private var editorWidth: String = "medium"

    static let sidebarWidth: CGFloat = 240
    /// Gap between the editor's page and the window edges.
    static let pageInset: CGFloat = 8
    static let pageShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    /// Minimum width for the editor detail column: the capped text column plus
    /// its side insets. Enforced as the detail column's min and folded into the
    /// window min width so the text column never reflows when the sidebar
    /// collapses/expands — the pane stays at or above the cap engagement point.
    private var detailMinWidth: CGFloat {
        WysiwygTextView.columnWidth(for: editorWidth) + WysiwygTextView.minSideInset * 2 + Self.pageInset * 2
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
                        // Our own toggle instead (SidebarView adds it; it stays
                        // beside the traffic lights when the sidebar collapses).
                        .toolbar(removing: .sidebarToggle)
                } detail: {
                    // The page floats on the window ground (design board ㉘ D6):
                    // the title and toolbar icons sit on the ground above it,
                    // and the page, inset 8 on the other three sides, holds
                    // only the text.
                    Group {
                        if appModel.showMemos {
                            MemosView()
                        } else {
                            EditorContainerView()
                        }
                    }
                        .clipShape(Self.pageShape)
                        .background {
                            Self.pageShape
                                .fill(Color.editorBg)
                                .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
                                .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                        }
                        .overlay {
                            Self.pageShape
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                        .padding([.leading, .trailing, .bottom], Self.pageInset)
                        .background(Color.windowGround)
                        .toolbarBackground(.hidden, for: .windowToolbar)
                    .navigationSplitViewColumnWidth(min: detailMinWidth, ideal: detailMinWidth, max: .infinity)
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
