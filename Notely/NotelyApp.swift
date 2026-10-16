import SwiftUI

@main
struct NotelyApp: App {
    @NSApplicationDelegateAdaptor(NotelyAppDelegate.self) private var appDelegate
    // Theme is global across all windows; the per-window data lives in WindowRoot.
    @State private var themeManager = ThemeManager.shared

    init() {
        // Don't have macOS restore every window from the last session on relaunch
        // (which would resurrect extra/empty windows). Launch opens a single
        // window restored to the last folder; opening more windows is manual
        // (⇧⌘N).
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            WindowRoot()
                .environment(themeManager)
                .task { themeManager.applyAppearance() }
        }
        // A standard unified toolbar window, so macOS 26+ draws the native
        // Liquid Glass toolbar and floating sidebar.
        .windowToolbarStyle(.unified)
        // A fresh install's first window; later launches restore the last size.
        .defaultSize(width: 1200, height: 800)
        .commands { AppCommands() }
    }
}

/// One window's root. Each window owns its OWN store / app model, so different
/// windows can open different folders and be edited in parallel.
struct WindowRoot: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var store = FileNoteStore()
    @State private var appModel = AppModel()
    @State private var settingsTabState = SettingsTabState()

    var body: some View {
        AppShellView()
            .background(WindowCloseBehavior(store: store).frame(width: 0, height: 0))
            .environment(store)
            .environment(appModel)
            .environment(settingsTabState)
            // One accent everywhere: Notely's own (Settings › Appearance),
            // not the system accent the native controls would otherwise pick.
            .tint(Color.accent)
            // Publish this window's store/model so menu commands act on the
            // focused window, not a shared global.
            .focusedSceneValue(\.noteStore, store)
            .focusedSceneValue(\.appModel, appModel)
            // Rebuild the shell (not the store) when the accent changes so the
            // accent-driven Color tokens are re-read everywhere. The @State above
            // lives on WindowRoot, which keeps its identity, so the open folder
            // and notes survive an accent switch.
            .id(themeManager.renderKey)
    }
}

// MARK: - Focused window values (so commands target the key window)

private struct NoteStoreFocusedKey: FocusedValueKey { typealias Value = FileNoteStore }
private struct AppModelFocusedKey: FocusedValueKey { typealias Value = AppModel }

extension FocusedValues {
    var noteStore: FileNoteStore? {
        get { self[NoteStoreFocusedKey.self] }
        set { self[NoteStoreFocusedKey.self] = newValue }
    }
    var appModel: AppModel? {
        get { self[AppModelFocusedKey.self] }
        set { self[AppModelFocusedKey.self] = newValue }
    }
}

// MARK: - Menu commands

struct AppCommands: Commands {
    @FocusedValue(\.noteStore) private var store
    @FocusedValue(\.appModel) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note") {
                guard let store, let appModel else { return }
                appModel.openNote(store.createNote()?.id)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open Folder…") {
                openFolderInFocusedWindow()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .importExport) {
            Button("Export All Notes…") {
                guard let store else { return }
                NoteExporter.exportAll(store.notes)
            }
            .disabled(store == nil)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { appModel?.showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(appModel == nil)
        }

        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") { appModel?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Search Notes") {
                guard let appModel else { return }
                appModel.presentSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
        }

        CommandMenu("Format") {
            // Send straight to the first responder (the focused window's text
            // view) so the action fires exactly once. Broadcasting via
            // NotificationCenter would hit every open window's editor.
            Button("Bold") { NSApp.sendAction(#selector(WysiwygTextView.toggleBold(_:)), to: nil, from: nil) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { NSApp.sendAction(#selector(WysiwygTextView.toggleItalic(_:)), to: nil, from: nil) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Insert Link") { NSApp.sendAction(#selector(WysiwygTextView.insertLink), to: nil, from: nil) }
                .keyboardShortcut("k", modifiers: .command)
            Button("Toggle Todo") { NSApp.sendAction(#selector(WysiwygTextView.toggleTodoOnCurrentLine), to: nil, from: nil) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }

    /// Opens a folder in the currently focused window (replacing its workspace).
    /// If no window is focused, opens a new window for the chosen folder instead.
    private func openFolderInFocusedWindow() {
        guard let url = NotesFolderPanel.choose() else { return }
        if let store, let appModel {
            store.openWorkspace(at: url)
            appModel.openNote(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

extension Notification.Name {
    static let newNote = Notification.Name("notely.newNote")
    static let formatBold = Notification.Name("notely.formatBold")
    static let formatItalic = Notification.Name("notely.formatItalic")
    static let formatLink = Notification.Name("notely.formatLink")
    static let toggleTodo = Notification.Name("notely.toggleTodo")
}
