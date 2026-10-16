import Foundation

/// Pure decision helpers for reconciling on-disk file changes (made by an
/// external editor) with what the in-app editor is showing. Kept free of AppKit
/// / SwiftUI so it can be unit-tested standalone.
enum ExternalSync {

    // MARK: - Editor reconciliation

    /// What to do when the open note's on-disk content changes underneath the
    /// editor.
    enum Decision: Equatable {
        /// On-disk content already matches what's displayed (includes the echo of
        /// the app's own save). Nothing to load; just record that we're in sync.
        case ignore
        /// The editor has no unsaved local edits, so the external change can be
        /// pulled in safely.
        case adopt
        /// The editor has unsaved local edits that diverge from disk. Keep them —
        /// the pending save will write them out — rather than clobbering the user.
        case keepLocal
    }

    /// - Parameters:
    ///   - disk: the latest content read from the file.
    ///   - displayed: what the editor is currently showing.
    ///   - lastSynced: the content the editor last loaded or saved (its view of
    ///     what is on disk).
    static func resolve(disk: String, displayed: String, lastSynced: String) -> Decision {
        if disk == displayed { return .ignore }
        if displayed == lastSynced { return .adopt }
        return .keepLocal
    }

    // MARK: - File-system event filtering

    /// Whether a batch of file-system event paths represents a change the app did
    /// not make itself. Used to skip the rescan that our own debounced saves would
    /// otherwise trigger on every keystroke window.
    ///
    /// - Parameters:
    ///   - eventPaths: paths reported by the watcher.
    ///   - selfSaved: paths the app wrote recently (and whose on-disk content it
    ///     therefore already knows).
    static func hasExternalChange(eventPaths: [String], selfSaved: Set<String>) -> Bool {
        let edited = eventPaths.filter {
            let ext = ($0 as NSString).pathExtension.lowercased()
            return ext == "md" || ext == "markdown"
        }
        // No note files in the batch (e.g. a bare directory event) → reload to be
        // safe; it might be a create/delete/rename we should reflect.
        guard !edited.isEmpty else { return true }
        return !edited.allSatisfy { selfSaved.contains($0) }
    }
}
