import Foundation

// Standalone test runner for ExternalSync. There is no Xcode test target in this
// project, and ExternalSync has no AppKit dependency, so it compiles directly
// with its source file:
//
//     swiftc Notely/Services/ExternalSync.swift Tests/ExternalSyncTests.swift -o /tmp/externalsync-tests
//     /tmp/externalsync-tests
//
// Exits non-zero if any assertion fails.

@main
enum ExternalSyncTests {
    static var failures = 0
    static var checks = 0

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        checks += 1
        if actual != expected {
            failures += 1
            print("FAIL: \(message) — got \(actual), expected \(expected)")
        }
    }

    static func main() {
        testResolve()
        testHasExternalChange()

        if failures == 0 {
            print("OK: all \(checks) checks passed")
        } else {
            print("\(failures)/\(checks) checks FAILED")
            exit(1)
        }
    }

    // MARK: - resolve(disk:displayed:lastSynced:)

    static func testResolve() {
        // Disk equals what's shown — our own save echo / already in sync.
        expect(ExternalSync.resolve(disk: "a", displayed: "a", lastSynced: "a"),
               .ignore, "in sync → ignore")
        expect(ExternalSync.resolve(disk: "a", displayed: "a", lastSynced: "old"),
               .ignore, "disk == displayed even with stale lastSynced → ignore")

        // Clean editor (displayed == lastSynced) but disk moved → adopt.
        expect(ExternalSync.resolve(disk: "new", displayed: "old", lastSynced: "old"),
               .adopt, "clean editor + external change → adopt")

        // Editor has unsaved local edits that diverge from disk → keep local.
        expect(ExternalSync.resolve(disk: "external", displayed: "myedit", lastSynced: "old"),
               .keepLocal, "local edits + external change → keepLocal")

        // Local edits that happen to match disk are caught by the first rule.
        expect(ExternalSync.resolve(disk: "same", displayed: "same", lastSynced: "old"),
               .ignore, "local edit converged with disk → ignore")
    }

    // MARK: - hasExternalChange(eventPaths:selfSaved:)

    static func testHasExternalChange() {
        // A note we just saved ourselves → not external.
        expect(ExternalSync.hasExternalChange(eventPaths: ["/w/a.md"], selfSaved: ["/w/a.md"]),
               false, "only our own save → not external")

        // A note changed that we did not write → external.
        expect(ExternalSync.hasExternalChange(eventPaths: ["/w/a.md"], selfSaved: []),
               true, "unknown md change → external")

        // Mixed: one ours, one external → external (don't suppress).
        expect(ExternalSync.hasExternalChange(eventPaths: ["/w/a.md", "/w/b.md"], selfSaved: ["/w/a.md"]),
               true, "one external among ours → external")

        // Non-note files only → conservatively treat as external (covers dir
        // events for create/delete/rename we should reflect).
        expect(ExternalSync.hasExternalChange(eventPaths: ["/w/.git/index"], selfSaved: []),
               true, "no md paths → reload to be safe")

        // .markdown extension is recognized too.
        expect(ExternalSync.hasExternalChange(eventPaths: ["/w/a.markdown"], selfSaved: ["/w/a.markdown"]),
               false, ".markdown self-save → not external")
    }
}
