import Foundation

/// A folder (notebook) in the sidebar's notes tree. Folders mirror the
/// workspace's subdirectories; `id` is the folder's path relative to the
/// workspace root ("/" for the root, "/产品思考/草稿" for a nested one).
struct NoteFolder: Identifiable, Equatable {
    let id: String
    let name: String
    var folders: [NoteFolder] = []
    var notes: [FileNote] = []

    /// Notes in this folder and every folder below it.
    var totalCount: Int {
        notes.count + folders.reduce(0) { $0 + $1.totalCount }
    }
}

enum NoteTreeBuilder {
    /// Groups notes into a folder tree by their `relativePath`. Notes keep the
    /// order they were passed in (the caller sorts them); folders are sorted by
    /// name the way Finder does.
    static func build(from notes: [FileNote]) -> NoteFolder {
        var root = NoteFolder(id: "/", name: "")
        for note in notes {
            let components = note.relativePath.split(separator: "/").map(String.init)
            insert(note, at: components[...], into: &root)
        }
        sortFolders(&root)
        return root
    }

    private static func insert(_ note: FileNote, at path: ArraySlice<String>, into folder: inout NoteFolder) {
        guard let head = path.first else {
            folder.notes.append(note)
            return
        }
        let childId = (folder.id == "/" ? "" : folder.id) + "/" + head
        if let idx = folder.folders.firstIndex(where: { $0.id == childId }) {
            insert(note, at: path.dropFirst(), into: &folder.folders[idx])
        } else {
            var child = NoteFolder(id: childId, name: head)
            insert(note, at: path.dropFirst(), into: &child)
            folder.folders.append(child)
        }
    }

    private static func sortFolders(_ folder: inout NoteFolder) {
        folder.folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for i in folder.folders.indices {
            sortFolders(&folder.folders[i])
        }
    }

    /// Every folder id from the root down to (and including) the folder that
    /// holds a note at `relativePath`. Used to auto-expand the path to the
    /// selected note.
    static func ancestorIds(ofRelativePath relativePath: String) -> [String] {
        var ids: [String] = []
        var current = ""
        for component in relativePath.split(separator: "/") {
            current += "/" + component
            ids.append(current)
        }
        return ids
    }
}
