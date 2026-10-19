import SwiftUI
import UniformTypeIdentifiers

/// The note's title in the toolbar — or, once more than one page is open,
/// the tab strip in its place (design board ㊴ B). Every page type puts this
/// in its toolbar, so the strip shows over notes, Memos and file previews.
struct NoteTitleHeader: ToolbarContent {
    var title: String = ""
    var subtitle: String = ""
    @Environment(AppModel.self) private var appModel
    @AppStorage("notely.editorFont") private var editorFontName: String = "System"

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            FlatToolbarItem(placement: .navigation, glassInGlassTheme: false) {
                if appModel.showsTabStrip {
                    TabStrip()
                } else if !title.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.styledTitle(title, fontName: editorFontName))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.notely(11))
                                .foregroundColor(.faintText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.leading, 6)
                }
            }
            ToolbarSpacer(.flexible)
        } else if appModel.showsTabStrip {
            ToolbarItem(placement: .navigation) { TabStrip() }
        }
    }

    /// `title` in the body family at 13.5pt medium.
    static func styledTitle(_ title: String, fontName: String) -> AttributedString {
        BodyFace.text(title, fontName: fontName, size: 13.5, weight: .medium)
    }
}

/// The row of paper tabs. The active tab is the page's own color and its
/// lower corners flare out into the page, so it reads as an index tab of
/// the sheet below; the others are gray titles on the ground, split by
/// hairlines. Tabs share the width between 96 and 208 points, then scroll,
/// with ⌄ listing them all.
struct TabStrip: View {
    @Environment(AppModel.self) private var appModel
    @Environment(FileNoteStore.self) private var store
    @State private var hoveredTab: UUID?
    @State private var draggedTab: UUID?

    static let height: CGFloat = 52
    static let tabHeight: CGFloat = 36
    static let pinnedWidth: CGFloat = 42
    static let maxTabWidth: CGFloat = 208
    static let minTabWidth: CGFloat = 96
    /// From the strip's leading edge to the first tab, room for its flare.
    static let leadingInset: CGFloat = 14
    /// The ⌄ button after the tabs, when they overflow.
    static let buttonWidth: CGFloat = 28

    private var stripWidth: CGFloat { max(240, appModel.tabStripWidth) }

    private var layout: (tabWidth: CGFloat, overflows: Bool) {
        let pinned = appModel.tabs.filter(\.isPinned).count
        let unpinned = appModel.tabs.count - pinned
        let room = stripWidth - Self.leadingInset - 10 - Self.buttonWidth - CGFloat(pinned) * Self.pinnedWidth
        guard unpinned > 0 else { return (Self.maxTabWidth, false) }
        let share = (room / CGFloat(unpinned)).rounded(.down)
        return (min(Self.maxTabWidth, max(Self.minTabWidth, share)), share < Self.minTabWidth)
    }

    var body: some View {
        let layout = layout
        HStack(alignment: .bottom, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(appModel.tabs.enumerated()), id: \.element.id) { index, tab in
                            chip(tab, at: index, width: layout.tabWidth)
                                .id(tab.id)
                        }
                    }
                    .padding(.leading, Self.leadingInset)
                    .padding(.trailing, 10)
                    .frame(height: Self.height, alignment: .bottomLeading)
                }
                .scrollDisabled(!layout.overflows)
                .mask(fade(on: layout.overflows))
                .onChange(of: appModel.activeTabId, initial: true) { _, id in
                    guard layout.overflows else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // New pages come from the toolbar's New Note, as with one page.
            if layout.overflows {
                allTabsMenu
                    .padding(.bottom, 4)
            }
        }
        .frame(width: stripWidth, height: Self.height, alignment: .bottomLeading)
        .animation(.easeOut(duration: 0.18), value: appModel.tabs)
    }

    private func chip(_ tab: NoteTab, at index: Int, width: CGFloat) -> some View {
        let isActive = tab.id == appModel.activeTabId
        let next = appModel.tabs.indices.contains(index + 1) ? appModel.tabs[index + 1].id : nil
        let raised: Set<UUID?> = [appModel.activeTabId, hoveredTab]
        let showsSeparator = next != nil && !raised.contains(tab.id) && !raised.contains(next)
        return PaperTab(tab: tab,
                        title: title(of: tab),
                        help: help(for: tab),
                        glyph: glyph(of: tab),
                        isActive: isActive,
                        isHovered: hoveredTab == tab.id,
                        width: tab.isPinned ? Self.pinnedWidth : width)
            .overlay(alignment: .trailing) {
                if showsSeparator {
                    Rectangle()
                        .fill(Color.primaryText.opacity(0.16))
                        .frame(width: 1, height: 14)
                        .padding(.bottom, 11)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(x: 0.5)
                }
            }
            .onHover { hovering in
                if hovering { hoveredTab = tab.id } else if hoveredTab == tab.id { hoveredTab = nil }
            }
            .onDrag {
                draggedTab = tab.id
                return NSItemProvider(object: tab.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: TabDropDelegate(target: tab.id, dragged: $draggedTab, appModel: appModel))
            .contextMenu { menu(for: tab) }
    }

    @ViewBuilder private func menu(for tab: NoteTab) -> some View {
        Button("Close Tab") { appModel.closeTab(tab.id) }
            .disabled(tab.isPinned)
        Button("Close Other Tabs") { appModel.closeOtherTabs(tab.id) }
            .disabled(appModel.tabs.allSatisfy { $0.id == tab.id || $0.isPinned })
        Button("Close Tabs to the Right") { appModel.closeTabsToTheRight(of: tab.id) }
            .disabled(appModel.tabs.last?.id == tab.id)
        Divider()
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { appModel.togglePin(tab.id) }
        if let url = url(of: tab) {
            Button("Reveal in Sidebar") {
                appModel.selectTab(tab.id)
                if !appModel.isSidebarVisible { appModel.toggleSidebar() }
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private var allTabsMenu: some View {
        Menu {
            ForEach(appModel.tabs) { tab in
                Button {
                    appModel.selectTab(tab.id)
                } label: {
                    if tab.id == appModel.activeTabId {
                        Label(title(of: tab), systemImage: "checkmark")
                    } else {
                        Text(title(of: tab))
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondaryText)
                .frame(width: Self.buttonWidth, height: Self.buttonWidth)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("All Tabs")
    }

    /// Tabs that scroll fade out at the trailing edge.
    private func fade(on: Bool) -> some View {
        LinearGradient(stops: [.init(color: .black, location: 0),
                               .init(color: .black, location: on ? 0.94 : 1),
                               .init(color: on ? .clear : .black, location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    // MARK: What each tab shows

    private func note(_ tab: NoteTab) -> FileNote? {
        guard case .note(let id) = tab.content else { return nil }
        return store.notes.first { $0.id == id }
    }

    private func file(_ tab: NoteTab) -> LibraryFile? {
        guard case .file(let id) = tab.content else { return nil }
        return store.files.first { $0.id == id }
    }

    private func title(of tab: NoteTab) -> String {
        switch tab.content {
        case .draft: "Untitled"
        case .memos: "Memos"
        case .note(let id): note(tab)?.filename ?? ((id as NSString).lastPathComponent as NSString).deletingPathExtension
        case .file(let id): (id as NSString).lastPathComponent
        }
    }

    /// The hover tip: the full title and what the single-tab header showed
    /// under it — folder and edit date.
    private func help(for tab: NoteTab) -> String {
        if let note = note(tab) {
            let folder = note.relativePath.split(separator: "/").joined(separator: " / ")
            let edited = NoteToolbar.editedLabel(for: note.updatedAt)
            return "\(note.filename)\n" + (folder.isEmpty ? edited : "\(folder) · \(edited)")
        }
        if let file = file(tab) {
            return "\(file.name)\n" + NoteToolbar.editedLabel(for: file.updatedAt)
        }
        return title(of: tab)
    }

    private func glyph(of tab: NoteTab) -> ShiyeGlyph {
        switch tab.content {
        case .draft, .note: .note
        case .memos: .memo
        case .file:
            switch file(tab)?.kind {
            case .image: .image
            case .video: .video
            default: .file
            }
        }
    }

    private func url(of tab: NoteTab) -> URL? {
        note(tab)?.url ?? file(tab)?.url
    }
}

/// One tab. Active: the page-colored index tab; hovered: a faint fill and
/// the close button. Pinned tabs show their icon only and can't be closed
/// from here.
private struct PaperTab: View {
    let tab: NoteTab
    let title: String
    let help: String
    let glyph: ShiyeGlyph
    let isActive: Bool
    let isHovered: Bool
    let width: CGFloat
    @Environment(AppModel.self) private var appModel
    @AppStorage("notely.editorFont") private var editorFontName: String = "System"
    @State private var isHoveringClose = false

    private var showsClose: Bool { !tab.isPinned && (isActive || isHovered) }

    var body: some View {
        Button {
            appModel.selectTab(tab.id)
        } label: {
            label
                .frame(width: width, height: TabStrip.tabHeight)
                .background(alignment: .bottom) { background }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if showsClose {
                Button {
                    appModel.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(isHoveringClose ? .primaryText : .iconMuted)
                        .frame(width: 16, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isHoveringClose ? Color.primaryText.opacity(0.10) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClose = $0 }
                .padding(.trailing, 7)
                .help("Close Tab (⌘W)")
                .accessibilityLabel("Close \(title)")
            }
        }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder private var label: some View {
        if tab.isPinned {
            ShiyeIcon(glyph, size: 16)
                .foregroundColor(isActive ? .secondaryText : .iconMuted)
                .frame(maxWidth: .infinity)
        } else {
            Text(BodyFace.text(title, fontName: editorFontName, size: 13, weight: .medium))
                .italic(tab.content == .draft)
                .foregroundColor(isActive ? .secondaryText : .tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 14)
                .padding(.trailing, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var background: some View {
        if isActive {
            PaperTabShape(flare: PaperTabShape.flare)
                .fill(Color.pageSheet)
                .frame(width: width + PaperTabShape.flare * 2, height: TabStrip.tabHeight)
        } else if isHovered {
            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10, style: .continuous)
                .fill(Color.primaryText.opacity(0.04))
        }
    }
}

/// An index tab with rounded top corners whose lower corners curve outward
/// into the page below (`flare` wide on each side).
struct PaperTabShape: Shape {
    static let flare: CGFloat = 10
    var flare: CGFloat
    var radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, f = flare, r = radius
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        p.addArc(center: CGPoint(x: 0, y: h - f), radius: f,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: f, y: r))
        p.addArc(center: CGPoint(x: f + r, y: r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: w - f - r, y: 0))
        p.addArc(center: CGPoint(x: w - f - r, y: r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w - f, y: h - f))
        p.addArc(center: CGPoint(x: w, y: h - f), radius: f,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Dragging a tab over another moves it to that place, live.
private struct TabDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragged: UUID?
    let appModel: AppModel

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target,
              let to = appModel.tabs.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.easeOut(duration: 0.16)) { appModel.moveTab(dragged, to: to) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
