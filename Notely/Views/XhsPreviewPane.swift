import AppKit
import SwiftUI
import WebKit

/// The publish preview beside the page: the WeChat article or the
/// Xiaohongshu cards. With both extensions on, a switch on top chooses, and
/// each note keeps its choice (board ㊾).
struct PublishPreviewPane: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(AppSettings.wechatExtensionKey) private var wechatEnabled = false
    @AppStorage(AppSettings.xhsExtensionKey) private var xhsEnabled = false

    static let width: CGFloat = 420

    var body: some View {
        let target = appModel.publishTarget(for: appModel.selectedNoteId)
        VStack(spacing: 0) {
            if wechatEnabled && xhsEnabled {
                HStack {
                    PreviewSwitch(selection: target) { appModel.setPublishTarget($0, for: appModel.selectedNoteId) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.primaryText.opacity(0.07)).frame(height: 1) }
            }
            switch target {
            case .wechat: WeChatPreviewPane()
            case .xiaohongshu: XhsPreviewPane()
            }
        }
        .background(Color.quietSurface)
    }
}

/// WeChat | Xiaohongshu: a faint track with the chosen side as a white
/// segment, like the choices in Settings.
private struct PreviewSwitch: View {
    let selection: AppModel.PublishTarget
    let choose: (AppModel.PublishTarget) -> Void
    @Namespace private var segment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppModel.PublishTarget.allCases, id: \.self) { target in
                let isSelected = target == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { choose(target) }
                } label: {
                    Text(target == .wechat ? "WeChat" : "Xiaohongshu")
                        .font(.notely(.caption, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? .primaryText : .secondaryText)
                        .padding(.horizontal, 11)
                        .frame(height: 22)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "segment", in: segment)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primaryText.opacity(0.07)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Publish to")
    }
}

/// The Xiaohongshu side of the preview (board ㊾ ①): the template, the
/// post's title and its length, the cards two by two, the caption, Export.
struct XhsPreviewPane: View {
    @Environment(AppModel.self) private var appModel
    @Environment(FileNoteStore.self) private var store
    // Read so the cards redraw when Settings changes.
    @AppStorage(AppSettings.xhsTemplateKey) private var defaultTemplate = XhsCards.Template.memo.rawValue
    @AppStorage(AppSettings.xhsRatioKey) private var defaultRatio = XhsCards.Ratio.portrait.rawValue
    @AppStorage(AppSettings.xhsPageNumbersKey) private var pageNumbers = true
    @AppStorage(AppSettings.xhsNameKey) private var name = ""
    @AppStorage(AppSettings.xhsHandleKey) private var handle = ""
    @AppStorage(AppSettings.xhsAvatarKey) private var avatar = ""
    @AppStorage(AppSettings.xhsEndCardKey) private var endCard = false
    @AppStorage(AppSettings.xhsEndLineKey) private var endLine = ""

    @State private var choices = XhsCards.NoteChoices()
    @State private var choicesNote: String?
    @State private var deck: XhsDeck?
    @State private var layoutWarnings: [String] = []
    @State private var cardCount = 0
    @State private var status: String?
    @State private var isWorking = false
    @State private var exportAnchor: NSView?

    private var noteId: String? { appModel.previewNote?.noteId }

    /// Read in the body so that a change in Settings lays the cards out again.
    private var settings: String {
        "\(defaultTemplate)|\(defaultRatio)|\(pageNumbers)|\(name)|\(handle)|\(avatar)|\(endCard)|\(endLine)"
    }

    var body: some View {
        let _ = settings
        VStack(spacing: 0) {
            header
            if let deck { titleRow(deck) }
            notice
            if let deck {
                XhsCardsView(input: XhsCards.input(for: deck, choices: choices), onLayout: { count, warnings in
                    cardCount = count
                    layoutWarnings = warnings
                }, menu: cardMenu)
                captionBox(deck)
            } else {
                Spacer()
            }
        }
        .task(id: appModel.previewNote) { rebuild() }
        .onChange(of: choices) { _, value in
            if let noteId, noteId == choicesNote { XhsCards.setChoices(value, for: noteId) }
        }
        .onReceive(NotificationCenter.default.publisher(for: XhsCards.statusNotification)) { notification in
            if let message = notification.object as? String { flash(message) }
        }
    }

    private func rebuild() {
        guard let note = appModel.previewNote else { deck = nil; return }
        if choicesNote != note.noteId {
            choices = XhsCards.choices(for: note.noteId)
            choicesNote = note.noteId
        }
        deck = XhsCards.deck(for: note, choices: choices)
    }

    // MARK: - Header

    private var template: XhsCards.Template { XhsCards.template(for: choices) }
    private var ratio: XhsCards.Ratio { XhsCards.ratio(for: choices) }

    private var header: some View {
        HStack(spacing: 13) {
            ForEach(XhsCards.Template.allCases) { option in
                ThemeWord(title: option.name, isSelected: option == template) {
                    choices.template = option == XhsCards.template(for: XhsCards.NoteChoices()) ? nil : option.rawValue
                    rebuild()
                }
            }
            Spacer(minLength: 6)
            Button(ratio.rawValue) {
                let next: XhsCards.Ratio = ratio == .portrait ? .square : .portrait
                choices.ratio = next == XhsCards.ratio(for: XhsCards.NoteChoices()) ? nil : next.rawValue
                rebuild()
            }
            .buttonStyle(.plain)
            .font(.notely(.caption))
            .foregroundColor(.secondaryText)
            .help("Card size: 3:4 or 1:1")
            Button {
                showExportMenu()
            } label: {
                HStack(spacing: 4) {
                    Text(isWorking ? "Exporting…" : "Export")
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
            }
            .buttonStyle(CopyButtonStyle())
            .disabled(deck == nil || isWorking)
            .background(AnchorView(view: $exportAnchor))
            .help("Export the cards (⌥⌘C adds them to Photos)")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primaryText.opacity(0.07)).frame(height: 1) }
    }

    private func titleRow(_ deck: XhsDeck) -> some View {
        let title = XhsCards.title(deck, choices)
        let count = XhsCards.length(title)
        return HStack(spacing: 10) {
            TextField(deck.title, text: Binding(
                get: { title },
                set: { choices.title = $0 == deck.title ? nil : $0 }
            ))
            .textFieldStyle(.plain)
            .font(.notely(.caption))
            .foregroundColor(.secondaryText)
            .help("The post's title. Changing it here doesn't change the note.")
            Text("\(count)")
                .font(.notely(.caption).monospacedDigit())
                .foregroundColor(.tertiaryText)
                .help("Characters in the title")
            QuietLink(title: "Copy title") { XhsCards.copyText(title) }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primaryText.opacity(0.07)).frame(height: 1) }
    }

    @ViewBuilder
    private var notice: some View {
        let warnings = (deck?.warnings ?? []) + layoutWarnings
        let leftOut = deck?.leftOutCount ?? 0
        if status != nil || !warnings.isEmpty || leftOut > 0 {
            VStack(alignment: .leading, spacing: 4) {
                if let status {
                    Text(status).foregroundColor(.primaryText)
                }
                ForEach(warnings, id: \.self) { Text($0) }
                if leftOut > 0 {
                    HStack(spacing: 8) {
                        Text(leftOut == 1 ? "1 part left out of the cards." : "\(leftOut) parts left out of the cards.")
                        QuietLink(title: "Put Back") {
                            choices.leftOut = []
                            rebuild()
                        }
                    }
                }
            }
            .font(.notely(.caption))
            .foregroundColor(Color(nsColor: .adaptive(light: 0x7A5A12, dark: 0xE2C47A)))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(nsColor: .adaptive(light: 0xFBF6EA, dark: 0x3A3220)))
        }
    }

    private func captionBox(_ deck: XhsDeck) -> some View {
        let caption = XhsCards.caption(deck, choices)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Caption").font(.notely(.caption, weight: .semibold)).foregroundColor(.primaryText)
                Text("\(XhsCards.length(caption))")
                    .font(.notely(.caption).monospacedDigit())
                    .foregroundColor(.tertiaryText)
                    .help("Characters in the caption")
                Spacer()
                if choices.caption != nil {
                    QuietLink(title: "Reset") { choices.caption = nil }
                }
                QuietLink(title: "Copy caption") { XhsCards.copyText(caption) }
            }
            TextEditor(text: Binding(
                get: { caption },
                set: { choices.caption = $0 == deck.caption ? nil : $0 }
            ))
            .font(.notely(.caption))
            .foregroundColor(.secondaryText)
            .scrollContentBackground(.hidden)
            .frame(height: 120)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .overlay(alignment: .top) { Rectangle().fill(Color.primaryText.opacity(0.07)).frame(height: 1) }
    }

    // MARK: - Export

    private func showExportMenu() {
        let count = max(cardCount, 1)
        let menu = NSMenu()
        let photos = ClosureMenuItem("Add \(count) Images to Photos") { export(.photos) }
        photos.keyEquivalent = "c"
        photos.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(photos)
        menu.addItem(ClosureMenuItem("AirDrop…") { export(.airDrop) })
        menu.addItem(ClosureMenuItem("Save Images to Folder…") { export(.folder) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Copy Caption") { copyCaption() })
        menu.addItem(ClosureMenuItem("Copy Title") { copyTitle() })
        if let anchor = exportAnchor {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.maxY + 4 : -4), in: anchor)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func copyCaption() {
        guard let deck else { return }
        XhsCards.copyText(XhsCards.caption(deck, choices))
        flash("Caption copied.")
    }

    private func copyTitle() {
        guard let deck else { return }
        XhsCards.copyText(XhsCards.title(deck, choices))
        flash("Title copied.")
    }

    private enum Destination { case photos, airDrop, folder }

    private func export(_ destination: Destination) {
        guard let deck, !isWorking else { return }
        let input = XhsCards.input(for: deck, choices: choices)
        let name = XhsCards.title(deck, choices)
        let caption = XhsCards.caption(deck, choices)
        let library = store.workspaceURL
        // Ask where first, so the cards render only once there's a place.
        var folder: URL?
        if destination == .folder {
            guard let chosen = XhsCards.chooseFolder(noteName: name, library: library) else { return }
            folder = chosen
        }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let files = try await XhsCards.renderFiles(input, name: name)
                switch destination {
                case .photos:
                    try await XhsCards.addToPhotos(files)
                    XhsCards.copyText(caption)
                    flash("\(files.count) images added to Photos. Caption copied.")
                case .airDrop:
                    if XhsCards.airDrop(files) {
                        XhsCards.copyText(caption)
                        flash("Caption copied.")
                    } else {
                        flash("AirDrop isn't available on this Mac.")
                    }
                case .folder:
                    guard let folder else { return }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    for file in files {
                        let target = folder.appendingPathComponent(file.lastPathComponent)
                        try? FileManager.default.removeItem(at: target)
                        try FileManager.default.copyItem(at: file, to: target)
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                    flash("\(files.count) images saved to \(folder.lastPathComponent).")
                }
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    private func flash(_ message: String) {
        withAnimation(.easeOut(duration: 0.15)) { status = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if status == message { withAnimation(.easeOut(duration: 0.2)) { status = nil } }
        }
    }

    // MARK: - A card's menu

    private func cardMenu(index: Int, ids: [String]) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Copy Image") { cardImage(index) { XhsCards.copyImage($0); flash("Image copied.") } })
        menu.addItem(ClosureMenuItem("Save Image…") {
            cardImage(index) { png in
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.nameFieldStringValue = String(format: "%02d.png", index + 1)
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do { try png.write(to: url) } catch { flash(error.localizedDescription) }
            }
        })
        if !ids.isEmpty {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Leave Out of Cards") {
                choices.leftOut = Array(Set(choices.leftOut).union(ids)).sorted()
                rebuild()
            })
        }
        return menu
    }

    private func cardImage(_ index: Int, then use: @escaping (Data) -> Void) {
        guard let deck else { return }
        let input = XhsCards.input(for: deck, choices: choices)
        Task { @MainActor in
            do {
                if let png = try await XhsRenderer.shared.render(input, only: index).first { use(png) }
            } catch {
                flash(error.localizedDescription)
            }
        }
    }
}

// MARK: - Parts

/// Hands back the NSView behind a SwiftUI view, to anchor a menu to it.
private struct AnchorView: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { self.view = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The cards, two by two, on a web view running cards.js. A new input lays
/// them out again; so does a new width.
private struct XhsCardsView: NSViewRepresentable {
    let input: XhsCards.Input
    let onLayout: (Int, [String]) -> Void
    let menu: (Int, [String]) -> NSMenu

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CardsWebView {
        let configuration = XhsAssets.configuration()
        configuration.userContentController.add(context.coordinator, name: "xhs")
        let view = CardsWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.relayout() }
        context.coordinator.webView = view
        view.load(URLRequest(url: XhsAssets.pageURL))
        return view
    }

    func updateNSView(_ view: CardsWebView, context: Context) {
        context.coordinator.onLayout = onLayout
        context.coordinator.menu = menu
        context.coordinator.show(input)
    }

    static func dismantleNSView(_ view: CardsWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "xhs")
    }

    final class CardsWebView: WKWebView {
        var onWidthChange: (() -> Void)?
        private var lastWidth: CGFloat = 0

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            if abs(newSize.width - lastWidth) > 0.5 {
                lastWidth = newSize.width
                onWidthChange?()
            }
        }

        // The cards' own menu replaces the web view's.
        override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) { menu.removeAllItems() }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onLayout: ((Int, [String]) -> Void)?
        var menu: ((Int, [String]) -> NSMenu)?
        private var isLoaded = false
        private var shown: XhsCards.Input?
        private var pending: XhsCards.Input?
        private var isLayingOut = false

        func show(_ input: XhsCards.Input) {
            guard input != shown || pending != nil else { return }
            pending = input
            run()
        }

        func relayout() {
            guard let shown, pending == nil else { return }
            pending = shown
            run()
        }

        /// One layout at a time; the newest input waits for the one running.
        private func run() {
            guard isLoaded, !isLayingOut, let input = pending, let webView else { return }
            pending = nil
            shown = input
            isLayingOut = true
            Task { @MainActor in
                do {
                    let result = try await webView.callAsyncJavaScript("return await NotelyXhs.layout(JSON.parse(json))",
                                                                       arguments: ["json": input.json], in: nil, contentWorld: .page)
                    let object = result as? [String: Any] ?? [:]
                    onLayout?(object["count"] as? Int ?? 0, object["warnings"] as? [String] ?? [])
                } catch {
                    let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                    onLayout?(0, ["The cards couldn't be laid out: \(detail)"])
                }
                isLayingOut = false
                run()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            run()
        }

        /// Links never open inside the preview.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.navigationType == .linkActivated ? .cancel : .allow)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            // The cards laid out again once their images arrived.
            if body["type"] as? String == "layout" {
                onLayout?(body["count"] as? Int ?? 0, body["warnings"] as? [String] ?? [])
                return
            }
            guard body["type"] as? String == "menu", let index = body["index"] as? Int, let webView, let menu else { return }
            let ids = body["ids"] as? [String] ?? []
            let x = body["x"] as? Double ?? 0
            let y = body["y"] as? Double ?? 0
            let point = NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y)
            menu(index, ids).popUp(positioning: nil, at: point, in: webView)
            webView.evaluateJavaScript("NotelyXhs.menuClosed()")
        }
    }
}
