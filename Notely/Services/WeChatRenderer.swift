import CryptoKit
import Foundation
import JavaScriptCore

/// Lays out a note as a WeChat Official Account article with the
/// wechat-black-red skill's own renderer, bundled into Resources/WeChat by
/// Tools/wechat-renderer and run here in JavaScriptCore. The HTML is what
/// the skill's `render.mjs` writes as article.html: every style inline,
/// ready to paste into the WeChat editor.
///
/// Foundation-only, so Tests/WeChatRendererTests.swift runs it directly.
final class WeChatRenderer {
    /// The skill's fixed themes, by the name `render.mjs` takes.
    enum Theme: String, CaseIterable, Identifiable {
        case blackRed = "black-red"
        case blueprint
        case songti = "songti-supplement"
        case motionJournal = "motion-journal"

        var id: String { rawValue }

        var name: String {
            switch self {
            case .blackRed: "Black Red"
            case .blueprint: "Blueprint"
            case .songti: "Songti"
            case .motionJournal: "Motion"
            }
        }
    }

    struct Article: Equatable {
        /// The article body, all styles inline.
        let html: String
        /// From the note's leading `# H1` (left out of the body), its
        /// front matter title, or else its file name.
        let title: String
        /// What the renderer couldn't carry over cleanly, in its words.
        let warnings: [String]
    }

    struct RenderError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The renderer in the app's bundle; nil if the bundle lacks it.
    static let shared: WeChatRenderer? = Bundle.main.url(forResource: "WeChat", withExtension: nil)
        .flatMap { try? WeChatRenderer(folder: $0) }

    private let folder: URL
    private let context: JSContext
    private let renderFunction: JSValue
    /// JavaScriptCore runs one call at a time on this queue.
    private let queue = DispatchQueue(label: "notely.wechat-renderer", qos: .userInitiated)

    /// `folder` holds wechat-render.js and the skill's assets/.
    init(folder: URL) throws {
        self.folder = folder
        guard let context = JSContext() else { throw RenderError(message: "JavaScriptCore is unavailable.") }
        self.context = context
        context.setObject(Self.host(assets: folder), forKeyedSubscript: "__notelyHost" as NSString)
        let script = try String(contentsOf: folder.appendingPathComponent("wechat-render.js"), encoding: .utf8)
        context.evaluateScript(script)
        if let exception = context.exception {
            throw RenderError(message: "The WeChat renderer failed to load: \(exception)")
        }
        guard let render = context.objectForKeyedSubscript("NotelyWeChat")?.objectForKeyedSubscript("render"),
              !render.isUndefined else {
            throw RenderError(message: "The WeChat renderer is missing its render function.")
        }
        renderFunction = render
    }

    /// Renders `markdown`; local images resolve against `notePath`'s folder.
    func render(markdown: String, notePath: String, theme: Theme) throws -> Article {
        try queue.sync {
            context.exception = nil
            let options: [String: Any] = ["inputPath": notePath, "theme": theme.rawValue]
            let result = renderFunction.call(withArguments: [Self.separatingEmbeds(markdown), options])
            if let exception = context.exception {
                context.exception = nil
                let message = exception.objectForKeyedSubscript("message")?.toString() ?? exception.toString() ?? ""
                throw RenderError(message: message)
            }
            guard let json = result?.toString(), let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let html = object["html"] as? String else {
                throw RenderError(message: "The WeChat renderer returned nothing.")
            }
            return Article(html: html, title: object["title"] as? String ?? "",
                           warnings: object["warnings"] as? [String] ?? [])
        }
    }

    // MARK: - Embeds

    private static let embedLine = try! NSRegularExpression(pattern: #"^!\[[^\]\n]*\]\([^)\n]*\)$"#)

    /// `markdown` with a blank line before and after each line that holds
    /// only an image or video. The editor shows such a line as a block of
    /// its own even with text right under it; Markdown would run the two
    /// into one paragraph, and the renderer turns a video into its
    /// placeholder card only when it stands alone. Indented lines (inside a
    /// list) and fenced code stay as they are.
    static func separatingEmbeds(_ markdown: String) -> String {
        var lines: [String] = []
        var fence: String?
        var afterEmbed = false
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isBlank = trimmed.isEmpty
            if afterEmbed, !isBlank { lines.append("") }
            afterEmbed = false
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
            } else if !line.hasPrefix(" "), !line.hasPrefix("\t"),
                      embedLine.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
                if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
                afterEmbed = true
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Host

    /// What the bundle's node:fs and node:crypto shims call
    /// (Tools/wechat-renderer/shims).
    private static func host(assets: URL) -> [String: Any] {
        func value(_ object: Any?) -> JSValue {
            guard let context = JSContext.current() else { return JSValue() }
            return object.map { JSValue(object: $0, in: context) } ?? JSValue(nullIn: context)
        }
        func isFile(_ path: String) -> Bool {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        func sha256(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let skillAsset: @convention(block) (String) -> JSValue = { relative in
            guard !relative.split(separator: "/").contains("..") else { return value(nil) }
            return value(try? String(contentsOf: assets.appendingPathComponent(relative), encoding: .utf8))
        }
        let readText: @convention(block) (String) -> JSValue = { path in
            value(try? String(contentsOfFile: path, encoding: .utf8))
        }
        let readBase64: @convention(block) (String) -> JSValue = { path in
            value(FileManager.default.contents(atPath: path)?.base64EncodedString())
        }
        let fileExists: @convention(block) (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
        let isFileBlock: @convention(block) (String) -> Bool = { isFile($0) }
        let sha256Text: @convention(block) (String) -> String = { sha256(Data($0.utf8)) }
        let sha256File: @convention(block) (String) -> String = { sha256(FileManager.default.contents(atPath: $0) ?? Data()) }
        return [
            "skillAsset": skillAsset, "readText": readText, "readBase64": readBase64,
            "fileExists": fileExists, "isFile": isFileBlock, "sha256Text": sha256Text, "sha256File": sha256File,
        ]
    }
}
