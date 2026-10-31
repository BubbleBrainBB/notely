import Foundation

// Standalone test runner for WikiLink and WikiLinkIndex (links between
// notes, design board 58). Foundation-only, so it compiles on its own:
//
//   swiftc Notely/Services/WikiLink.swift Tests/WikiLinkTests.swift -o /tmp/wikilink-tests && /tmp/wikilink-tests

@main
enum WikiLinkTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition {
            failures += 1
            print("FAIL (line \(line)): \(message)")
        }
    }

    static func main() {
        // MARK: Parsing
        let plain = WikiLink("智谱 GLM-4.5v")
        check(plain?.target == "智谱 GLM-4.5v" && plain?.heading == nil && plain?.alias == nil, "plain target")
        let full = WikiLink("folder/Note.md#效果有多好？|上次那篇")
        check(full?.target == "folder/Note" && full?.heading == "效果有多好？" && full?.alias == "上次那篇",
              "path, .md, heading and alias: \(String(describing: full))")
        check(WikiLink("  ") == nil && WikiLink("#Heading") == nil, "nothing to link to")

        // MARK: What a link shows
        check(plain?.displayText(title: "GLM 那篇") == "GLM 那篇", "the note's title")
        check(full?.displayText(title: "Note") == "上次那篇", "the alias wins")
        check(WikiLink("Note#Part")?.displayText(title: "A Note") == "A Note › Part", "title › heading")
        check(WikiLink("a/b/Missing")?.displayText(title: nil) == "Missing", "a missing note shows its name")

        // MARK: Titles
        check(WikiLinkIndex.title(of: "---\ntitle: \"2025年7月4日\"\ndate: x\n---\n# Other\n", fileName: "f") == "2025年7月4日",
              "front matter title first")
        check(WikiLinkIndex.title(of: "---\ntags: [a]\n---\n\n# 标题\n正文", fileName: "f") == "标题", "then a first-line heading")
        check(WikiLinkIndex.title(of: "正文第一行\n\n# 中间的标题\n", fileName: "文件名") == "文件名",
              "a heading further down isn't the title")
        check(WikiLinkIndex.title(of: "", fileName: "文件名") == "文件名", "else the file name")

        // MARK: Resolving
        let root = URL(fileURLWithPath: "/lib")
        let index = WikiLinkIndex()
        index.update(notes: [
            ("/lib/a/Note.md", URL(fileURLWithPath: "/lib/a/Note.md"), "# In A"),
            ("/lib/b/c/Note.md", URL(fileURLWithPath: "/lib/b/c/Note.md"), "# In C"),
            ("/lib/Top.md", URL(fileURLWithPath: "/lib/Top.md"), "text"),
        ], library: root)
        check(index.resolve("top", from: nil)?.title == "Top", "by name, any case")
        check(index.resolve("Note", from: URL(fileURLWithPath: "/lib/b/c"))?.title == "In C", "same folder first")
        check(index.resolve("Note", from: URL(fileURLWithPath: "/lib/x"))?.title == "In A", "else nearest the top")
        check(index.resolve("b/c/Note", from: nil)?.title == "In C", "by library path")
        check(index.resolve("Gone", from: nil) == nil, "missing")

        let revision = index.revision
        index.update(notes: [
            ("/lib/Top.md", URL(fileURLWithPath: "/lib/Top.md"), "text"),
        ], library: root)
        index.update(notes: [
            ("/lib/Top.md", URL(fileURLWithPath: "/lib/Top.md"), "text"),
        ], library: root)
        check(index.revision == revision + 1, "an unchanged library isn't a change")

        if failures == 0 {
            print("All WikiLink tests passed")
        } else {
            print("\(failures) failure(s)")
            exit(1)
        }
    }
}
