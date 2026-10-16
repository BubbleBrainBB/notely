import Foundation

struct FileNote: Identifiable, Hashable {
    let id: String          // file URL path as unique ID
    let url: URL
    var title: String
    var content: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var pinned: Bool
    var relativePath: String  // path relative to workspace root, for display

    var filename: String {
        url.deletingPathExtension().lastPathComponent
    }
}
