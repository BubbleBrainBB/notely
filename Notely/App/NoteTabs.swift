import Foundation

/// One open page in a window (design board ㊴ B): a note, a blank draft,
/// the Memos page or a file preview. A window holds one or more.
struct NoteTab: Identifiable, Equatable, Codable {
    enum Content: Equatable, Codable {
        /// A blank page not yet on disk (board ㉝ E).
        case draft
        /// A note, by its id (the file path).
        case note(String)
        case memos
        /// An image, video or PDF, by its id (the file path).
        case file(String)

        /// The note or file path this tab shows, if any.
        var path: String? {
            switch self {
            case .note(let id), .file(let id): id
            case .draft, .memos: nil
            }
        }
    }

    var id = UUID()
    var content: Content
    /// Pinned tabs show only their icon and stay at the leading end.
    var isPinned = false
}

/// The tabs of a library, kept between launches: one set per library
/// folder, so reopening a folder brings its tabs back.
enum SavedTabs {
    private static let key = "notely.tabs"

    private struct Entry: Codable {
        var tabs: [NoteTab]
        var active: Int
    }

    static func load(workspace: String) -> (tabs: [NoteTab], active: Int)? {
        guard let all = UserDefaults.standard.dictionary(forKey: key),
              let data = all[workspace] as? Data,
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              !entry.tabs.isEmpty else { return nil }
        return (entry.tabs, min(max(entry.active, 0), entry.tabs.count - 1))
    }

    static func save(_ tabs: [NoteTab], active: Int, workspace: String) {
        guard let data = try? JSONEncoder().encode(Entry(tabs: tabs, active: active)) else { return }
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[workspace] = data
        UserDefaults.standard.set(all, forKey: key)
    }
}
