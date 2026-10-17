import AppKit
import SwiftUI

/// Keeps a red-X close from destroying the SwiftUI window/store while the app is
/// still running. This makes Dock re-open instant: the same window is shown
/// again instead of constructing a new store and rescanning the workspace.
final class NotelyAppDelegate: NSObject, NSApplicationDelegate {
    static var isQuitting = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Restoration can resurrect the windows that were open at last quit. For
        // the first moments of launch, discard any extra empty windows so only a
        // single workspace window remains.
        WindowCloseController.shared.beginLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⌃⌥N and the menu bar icon open the quick memo panel (design ㉛ ②).
        QuickCapture.shared.install()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.isQuitting = true
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        WindowCloseController.shared.handleDockReopen()
        return false
    }
}

private final class WindowCloseController: NSObject, NSWindowDelegate {
    static let shared = WindowCloseController()

    private let hiddenWindows = NSHashTable<NSWindow>.weakObjects()
    /// Windows already seen. `attach` runs again on every SwiftUI update of the
    /// window's root; only the first call may decide anything — otherwise the
    /// primary window of a first launch (no folder yet, so "empty") was taken
    /// for a stray restored window on its next update and closed, leaving the
    /// app with no window at all.
    private let attachedWindows = NSHashTable<NSWindow>.weakObjects()
    private var suppressEmptyWindowsUntil: Date?
    private var isDiscardingWindow = false
    /// The first window of a fresh launch becomes the primary: it restores the
    /// last workspace and is always kept. Consumed once per launch.
    private var pendingInitialRestore = true

    func beginLaunch() {
        suppressEmptyWindowsUntil = Date().addingTimeInterval(2)
    }

    func attach(to window: NSWindow, store: FileNoteStore) {
        guard !attachedWindows.contains(window) else { return }
        attachedWindows.add(window)
        window.delegate = self
        // Opt every window out of cross-launch state restoration so macOS does
        // not resurrect extra empty windows the next time the app launches.
        window.isRestorable = false

        if pendingInitialRestore {
            pendingInitialRestore = false
            restoreLastWorkspace(into: store)
            return
        }

        if shouldDiscardEmptyWindow(store: store) {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.discard(window)
            }
        }
    }

    /// Reopens the folder used in the previous session, into the primary window.
    private func restoreLastWorkspace(into store: FileNoteStore) {
        guard !store.isOpen else { return }
        let lastPath = AppSettings.workspacePath
        guard !lastPath.isEmpty else { return }
        let url = URL(fileURLWithPath: lastPath)
        // Not silently back to the welcome page as if the notes were gone:
        // the welcome page says which folder is missing and offers to find it.
        guard FileManager.default.fileExists(atPath: url.path) else {
            store.missingWorkspace = url
            return
        }
        store.openWorkspace(at: url)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if NotelyAppDelegate.isQuitting || isDiscardingWindow { return true }
        hiddenWindows.add(sender)
        sender.orderOut(nil)
        return false
    }

    func handleDockReopen() {
        // SwiftUI WindowGroup can still create replacement windows during Dock
        // reopen even after the app delegate handles the event. For this reopen
        // event only, discard those brand-new empty windows so reopening the Dock
        // icon restores the hidden workspace window instead of accumulating
        // extra Open Folder windows.
        suppressEmptyWindowsUntil = Date().addingTimeInterval(2)
        showHiddenWindows()
    }

    private func showHiddenWindows() {
        for window in hiddenWindows.allObjects where !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func shouldDiscardEmptyWindow(store: FileNoteStore) -> Bool {
        guard let suppressEmptyWindowsUntil,
              Date() <= suppressEmptyWindowsUntil else { return false }
        return !store.isOpen
    }

    private func discard(_ window: NSWindow) {
        isDiscardingWindow = true
        window.close()
        isDiscardingWindow = false
    }
}

struct WindowCloseBehavior: NSViewRepresentable {
    let store: FileNoteStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view, store] in
            if let window = view?.window {
                WindowCloseController.shared.attach(to: window, store: store)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView, store] in
            if let window = nsView?.window {
                WindowCloseController.shared.attach(to: window, store: store)
            }
        }
    }
}
