import Foundation

// Standalone test runner for NoteTreeBuilder / NoteSearch. No Xcode test target
// exists; both are Foundation-only, so this compiles directly with the sources:
//
//     swiftc Notely/Models/FileNote.swift Notely/Views/Sidebar/NoteTree.swift Tests/NoteTreeTests.swift -o /tmp/notetree-tests
//     /tmp/notetree-tests
//
// Exits non-zero if any assertion fails.

@main
enum NoteTreeTests {
    static var failures = 0
    static var checks = 0

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        checks += 1
        if actual != expected {
            failures += 1
            print("FAIL: \(message)\n  expected: \(expected)\n  actual:   \(actual)")
        }
    }

    static func note(_ title: String, in folder: String, tags: [String] = [], body: String = "") -> FileNote {
        let dir = folder == "/" ? "" : folder
        let url = URL(fileURLWithPath: "/ws\(dir)/\(title).md")
        return FileNote(id: url.path, url: url, title: title, content: "# \(title)\n\n\(body)",
                        tags: tags, createdAt: Date(), updatedAt: Date(), pinned: false,
                        relativePath: folder)
    }

    static func main() {
        // ── Tree building ──
        let notes = [
            note("Root B", in: "/"),
            note("Weekly", in: "/产品思考"),
            note("Draft", in: "/产品思考/草稿"),
            note("Root A", in: "/"),
            note("Kyoto", in: "/Travel"),
            note("Slow decisions", in: "/产品思考"),
        ]
        let root = NoteTreeBuilder.build(from: notes)

        expect(root.notes.map(\.title), ["Root B", "Root A"], "root notes keep input order")
        expect(root.folders.map(\.name), ["Travel", "产品思考"], "folders sorted by name")
        expect(root.folders.map(\.id), ["/Travel", "/产品思考"], "folder ids are relative paths")
        let product = root.folders[1]
        expect(product.notes.map(\.title), ["Weekly", "Slow decisions"], "folder notes keep input order")
        expect(product.folders.map(\.id), ["/产品思考/草稿"], "nested folder id")
        expect(product.totalCount, 3, "totalCount includes subfolders")
        expect(root.totalCount, 6, "root totalCount is every note")
        expect(NoteTreeBuilder.build(from: []).totalCount, 0, "empty workspace")

        expect(NoteTreeBuilder.ancestorIds(ofRelativePath: "/"), [], "root note has no ancestors")
        expect(NoteTreeBuilder.ancestorIds(ofRelativePath: "/产品思考/草稿"),
               ["/产品思考", "/产品思考/草稿"], "ancestor chain")

        // ── Search ──
        let tagged = [
            note("A", in: "/", tags: ["ai"]),
            note("B", in: "/", tags: ["ai/编程"]),
            note("C", in: "/", tags: ["aim"]),
            note("D", in: "/", body: "mentions Kyoto in the body"),
        ]
        expect(NoteSearch.filter(tagged, query: "#ai").map(\.title), ["A", "B"], "tag query matches tag and sub-tags only")
        expect(NoteSearch.filter(tagged, query: "#AI").map(\.title), ["A", "B"], "tag query is case-insensitive")
        expect(NoteSearch.filter(tagged, query: "#").count, 4, "bare # returns everything")
        expect(NoteSearch.filter(tagged, query: "kyoto").map(\.title), ["D"], "text query searches body")
        var renamed = note("Body", in: "/")
        renamed.title = "Opening sentence of a clipped article"
        expect(NoteSearch.filter([renamed], query: "body").count, 1, "text query matches the file name")
        expect(NoteSearch.filter(tagged, query: "  ").count, 4, "blank query returns everything")

        if failures == 0 {
            print("All \(checks) NoteTree checks passed.")
        } else {
            print("\(failures) of \(checks) NoteTree checks failed.")
            exit(1)
        }
    }
}
