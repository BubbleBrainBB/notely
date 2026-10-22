import AppKit
import SwiftUI
import WebKit

/// The WeChat Article extension (design boards ㊹–㊻ B): beside the page, a
/// second sheet showing the open note laid out for the WeChat Official
/// Account editor at phone width, redrawn as you type, with the theme and
/// Copy on top. Shown by AppShellView while the tab's preview is open.
struct WeChatPreviewPane: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(AppSettings.wechatThemeKey) private var themeName = WeChatRenderer.Theme.blackRed.rawValue
    @State private var article: WeChatRenderer.Article?
    @State private var failure: String?
    @State private var copied = false

    static let width: CGFloat = 420

    private var theme: WeChatRenderer.Theme { WeChatRenderer.Theme(rawValue: themeName) ?? .blackRed }

    private struct Request: Equatable {
        let note: AppModel.NoteText?
        let theme: WeChatRenderer.Theme
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let article, !article.title.isEmpty {
                titleRow(article.title)
            }
            if let notice = failure ?? article?.warnings.first.map(WeChatCopy.english) {
                Text(notice)
                    .font(.notely(11.5))
                    .foregroundColor(Color(nsColor: .adaptive(light: 0x7A5A12, dark: 0xE2C47A)))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(nsColor: .adaptive(light: 0xFBF6EA, dark: 0x3A3220)))
                    .help(failure ?? article?.warnings.map(WeChatCopy.english).joined(separator: "\n") ?? "")
            }
            ArticleWebView(html: article?.html ?? "")
                .opacity(failure == nil ? 1 : 0.35)
        }
        .background(Color.quietSurface)
        .task(id: Request(note: appModel.previewNote, theme: theme)) { await render() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ForEach(WeChatRenderer.Theme.allCases) { option in
                ThemeWord(title: option.name, isSelected: option == theme) { themeName = option.rawValue }
            }
            Spacer(minLength: 8)
            Button(copied ? "Copied" : "Copy", action: copy)
                .buttonStyle(CopyButtonStyle())
                .disabled(article == nil || failure != nil)
                .help("Copy for WeChat (⌥⌘C)")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primaryText.opacity(0.07)).frame(height: 1) }
    }

    /// WeChat takes the title in its own field: the article leaves it out,
    /// so it is offered here on its own.
    private func titleRow(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.notely(12))
                .foregroundColor(.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            QuietLink(title: "Copy title") { WeChatCopy.copyText(title) }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primaryText.opacity(0.07)).frame(height: 1) }
    }

    private func render() async {
        guard let note = appModel.previewNote else { return }
        do {
            let result = try await WeChatCopy.render(note, theme: theme)
            guard !Task.isCancelled else { return }
            article = result
            failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            failure = WeChatCopy.english(error.localizedDescription)
        }
    }

    private func copy() {
        guard let article, let note = appModel.previewNote else { return }
        WeChatCopy.copy(article, markdown: note.markdown)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

// MARK: - Copying

/// Rendering and the clipboard, shared by the preview's Copy and the
/// Copy for WeChat command.
enum WeChatCopy {
    static var theme: WeChatRenderer.Theme {
        WeChatRenderer.Theme(rawValue: UserDefaults.standard.string(forKey: AppSettings.wechatThemeKey) ?? "") ?? .blackRed
    }

    /// Off the main thread: a note with local images reads and encodes them.
    static func render(_ note: AppModel.NoteText, theme: WeChatRenderer.Theme) async throws -> WeChatRenderer.Article {
        // Off the main thread from the start: the first call also loads the renderer.
        try await Task.detached(priority: .userInitiated) {
            guard let renderer = WeChatRenderer.shared else {
                throw WeChatRenderer.RenderError(message: "The WeChat renderer is missing from this build.")
            }
            return try renderer.render(markdown: note.markdown, notePath: note.path, theme: theme)
        }.value
    }

    /// The article as rich text for the WeChat editor, with the Markdown as
    /// the plain-text fallback.
    static func copy(_ article: WeChatRenderer.Article, markdown: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(article.html, forType: .html)
        pasteboard.setString(markdown, forType: .string)
    }

    static func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// ⌥⌘C: copies the open note in the chosen theme without the preview.
    /// False when it can't be laid out (the preview then shows why).
    @MainActor
    static func copyOpenNote(_ appModel: AppModel) async -> Bool {
        guard let note = appModel.typedNote ?? appModel.previewNote, note.noteId == appModel.selectedNoteId,
              let article = try? await render(note, theme: theme) else { return false }
        copy(article, markdown: note.markdown)
        return true
    }

    /// Copies, or if the note can't be laid out, beeps and opens the
    /// preview, which says why.
    @MainActor
    static func copyOrShowWhy(_ appModel: AppModel) async {
        guard !(await copyOpenNote(appModel)) else { return }
        NSSound.beep()
        if !appModel.isWeChatPreviewOpen { appModel.toggleWeChatPreview() }
    }

    /// The renderer's notes are in Chinese (the skill's own words); the app
    /// speaks English.
    static func english(_ message: String) -> String {
        for (pattern, template) in translations {
            let range = NSRange(location: 0, length: (message as NSString).length)
            if let match = pattern.firstMatch(in: message, range: range) {
                return pattern.replacementString(for: match, in: message, offset: 0, template: template)
            }
        }
        return message
    }

    private static let translations: [(NSRegularExpression, String)] = [
        (#"^图片文件不存在：(.*)$"#, "Image not found: $1"),
        (#"^本地图片仅支持 PNG/JPEG/GIF/WebP：(.*)$"#, "Only PNG, JPEG, GIF and WebP images can go in the article: $1"),
        (#"^不支持的图片地址：(.*)$"#, "This image address can't go in the article: $1"),
        (#"^图片路径编码无效：(.*)$"#, "This image path isn't valid: $1"),
        (#"^YAML frontmatter 没有结束分隔线"#, "The note's front matter has no closing ---."),
        (#"^视频 (\d+) 的本地文件未找到：(.*)$"#, "Video $1 isn't on this Mac: $2"),
        (#"^有 (\d+) 处视频待在公众号后台插入"#, "$1 video placeholder(s): add each video in the WeChat editor, then remove its card."),
        (#"^含 (\d+) 个 SVG 动画"#, "$1 animated diagram(s): they play here; check them in WeChat before publishing."),
        (#"^存在 HTTP 图片"#, "Some images use http://. Prefer https:// and check them after pasting."),
        (#"^含 Base64 图片"#, "Embedded images go with the article. Check that WeChat keeps them after pasting."),
        (#"^本地图片已嵌入正文"#, "Images on this Mac go with the article. Check that WeChat keeps them after pasting."),
        (#"^含非 HTTP\(S\) 链接"#, "Some links aren't web addresses; they won't open in WeChat."),
        (#"^Obsidian Wiki 链接或嵌入未转换"#, "[[Links]] and ![[embeds]] stay as plain text."),
        (#"^脚注语法未转换"#, "Footnotes stay as plain text."),
        (#"^数学公式未排版"#, "Math stays as plain text."),
        (#"^存在未支持的 HTML"#, "HTML in the note shows as text; it isn't applied."),
        (#"^frontmatter 标题与开头 H1 不同"#, "The front matter title differs from the first heading; the heading is the title."),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
}

// MARK: - Parts

/// A theme's name; the chosen one dark and underlined in the accent, as in
/// Settings.
private struct ThemeWord: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.notely(12))
                .foregroundColor(isSelected ? .primaryText : (isHovering ? .secondaryText : .faintText))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.accent).frame(height: 1.5).offset(y: 4).opacity(isSelected ? 1 : 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct QuietLink: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.notely(11.5))
                .foregroundColor(isHovering ? .primaryText : .tertiaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The sheet's one solid button.
private struct CopyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.notely(12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accent.opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.8 : 1))
            )
            .contentShape(Rectangle())
    }
}

/// The article at phone width on a web view: what will be pasted, as it
/// will look. Updates swap the article in place, so the scroll stays put.
private struct ArticleWebView: NSViewRepresentable {
    let html: String

    private static let page = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="referrer" content="no-referrer">
    <style>
    html,body{margin:0;background:transparent}
    body{display:flex;justify-content:center;padding:14px 0 48px}
    #article{width:375px;background:#fff;border-radius:10px;overflow:hidden;
      box-shadow:0 0 0 1px rgba(0,0,0,.06),0 2px 10px rgba(0,0,0,.04)}
    </style></head><body><div id="article"></div></body></html>
    """

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        view.loadHTMLString(Self.page, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.show(html)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var isLoaded = false
        private var pending: String?
        private var shown: String?

        func show(_ html: String) {
            guard html != shown else { return }
            guard isLoaded, let webView else { pending = html; return }
            shown = html
            let literal = (try? JSONSerialization.data(withJSONObject: [html], options: []))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            webView.evaluateJavaScript("document.getElementById('article').innerHTML = \(literal)[0];")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let pending { self.pending = nil; show(pending) }
        }

        /// Links open in the browser, never inside the preview.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
