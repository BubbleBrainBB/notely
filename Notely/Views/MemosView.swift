import AppKit
import SwiftUI

/// The Memos page (design board ㉛ ①): write at the top, a quiet heatmap of
/// the last 22 weeks, then every memo, newest first, grouped by day. Memos
/// are stored one Markdown file per day in the library's Memos folder.
struct MemosView: View {
    @Environment(FileNoteStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @AppStorage(AppSettings.editorFontKey) private var editorFont = "System"

    @State private var selectedDay: String?
    @State private var selectedTag: String?

    static let columnWidth: CGFloat = 560

    /// Re-read so a font change in Settings restyles the page.
    private var textFont: Font {
        _ = editorFont
        return Font(MemoTypography.font(size: 15))
    }

    var body: some View {
        let memos = store.memos
        let counts = Dictionary(grouping: memos, by: \.day).mapValues(\.count)
        let shown = memos.filter { memo in
            (selectedDay == nil || memo.day == selectedDay) && (selectedTag == nil || memo.tags.contains(selectedTag!))
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MemoComposer { store.addMemo($0) }

                HStack {
                    Spacer(minLength: 0)
                    MemoHeatmapView(counts: counts, selectedDay: $selectedDay)
                }
                .padding(.top, 22)

                filterChips

                if memos.isEmpty {
                    Text("Memos are saved in the Memos folder, one file per day.")
                        .font(.notely(12))
                        .foregroundColor(.faintText)
                        .padding(.top, 28)
                }

                let groups = Self.groupedByDay(shown)
                ForEach(groups.indices, id: \.self) { index in
                    MemoDayGroup(day: groups[index].day, isFirst: index == 0) {
                        ForEach(groups[index].memos) { memo in
                            MemoRow(memo: memo, font: textFont, onTag: { tag in selectedTag = tag })
                        }
                    }
                }
                .padding(.top, 12)
            }
            .frame(width: Self.columnWidth)
            .padding(.top, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(Color.pageContentBg)
        .navigationTitle("Memos")
        .navigationSubtitle("")
        // No title header of its own; the tab strip when there are tabs.
        .modifier(MemosTabStrip())
    }

    @ViewBuilder private var filterChips: some View {
        if selectedDay != nil || selectedTag != nil {
            HStack(spacing: 8) {
                if let day = selectedDay {
                    FilterChip(label: Self.dayLabel(day, capitalized: true)) { selectedDay = nil }
                }
                if let tag = selectedTag {
                    FilterChip(label: "#" + tag) { selectedTag = nil }
                }
            }
            .padding(.top, 18)
        }
    }

    // MARK: Grouping and labels

    static func groupedByDay(_ memos: [Memo]) -> [(day: String, memos: [Memo])] {
        var groups: [(day: String, memos: [Memo])] = []
        for memo in memos {
            if groups.last?.day == memo.day {
                groups[groups.count - 1].memos.append(memo)
            } else {
                groups.append((memo.day, [memo]))
            }
        }
        return groups
    }

    /// "TODAY", "YESTERDAY", "OCT 14", or "OCT 14, 2025" for another year.
    static func dayLabel(_ day: String, capitalized: Bool = false) -> String {
        guard let date = MemoFormat.date(ofDay: day) else { return day }
        let calendar = Calendar.current
        let label: String
        if calendar.isDateInToday(date) {
            label = "Today"
        } else if calendar.isDateInYesterday(date) {
            label = "Yesterday"
        } else {
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
            label = date.formatted(sameYear ? .dateTime.month(.abbreviated).day()
                                            : .dateTime.month(.abbreviated).day().year())
        }
        return capitalized ? label : label.uppercased()
    }
}

// MARK: - Composer

/// The writing area: no title, grows with its text, ⌘↩ (or the arrow) adds
/// the memo to today's file.
struct MemoComposer: View {
    var placeholder = "Write it down…"
    let onSubmit: (String) -> Void
    @State private var draft = ""
    @State private var focusRequest = 1

    private var isEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MemoTextEditor(text: $draft, placeholder: placeholder, focusRequest: focusRequest, onSubmit: submit)
            HStack(spacing: 14) {
                Button {
                    draft += (draft.isEmpty || draft.hasSuffix(" ") || draft.hasSuffix("\n")) ? "#" : " #"
                    focusRequest += 1
                } label: {
                    ShiyeIcon(.tag, size: 15).foregroundColor(.iconMuted)
                }
                .buttonStyle(.plain)
                .help("Add a tag")
                Spacer(minLength: 0)
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(isEmpty ? Color.accent.opacity(0.22) : Color.accent))
                }
                .buttonStyle(.plain)
                .disabled(isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Save (⌘↩)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.sidebarBg))
    }

    private func submit() {
        guard !isEmpty else { return }
        onSubmit(draft)
        draft = ""
    }
}

// MARK: - Heatmap

/// 22 weeks of days, Monday at the top; a day's shade follows how many memos
/// it has, in the accent color. No numbers — hover a day for its count,
/// click it to see only that day.
struct MemoHeatmapView: View {
    let counts: [String: Int]
    @Binding var selectedDay: String?
    var weeks = 22
    var cell: CGFloat = 9
    var gap: CGFloat = 3

    private static let shades: [Double] = [0, 0.16, 0.32, 0.55, 0.85]

    var body: some View {
        let grid = MemoHeatmap.grid(weeks: weeks, endingAt: Date())
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(grid.indices, id: \.self) { index in
                    Text(monthLabel(grid, index))
                        .font(.notely(10))
                        .foregroundColor(.faintText)
                        .fixedSize()
                        .frame(width: cell, alignment: .leading)
                }
            }
            HStack(spacing: gap) {
                ForEach(grid.indices, id: \.self) { week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { weekday in
                            dayCell(grid[week][weekday])
                        }
                    }
                }
            }
        }
    }

    /// The month's name over the first week that starts in it.
    private func monthLabel(_ grid: [[Date?]], _ index: Int) -> String {
        guard let first = grid[index].first ?? nil else { return "" }
        let calendar = Calendar.current
        if index > 0, let previous = grid[index - 1].first ?? nil,
           calendar.component(.month, from: previous) == calendar.component(.month, from: first) {
            return ""
        }
        if index == 0, calendar.component(.day, from: first) > 7 { return "" }
        return first.formatted(.dateTime.month(.abbreviated))
    }

    @ViewBuilder private func dayCell(_ date: Date?) -> some View {
        if let date {
            let day = MemoFormat.day(of: date)
            let count = counts[day] ?? 0
            let level = MemoHeatmap.level(for: count)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(level == 0 ? Color.inlineFill : Color.accent.opacity(Self.shades[level]))
                .frame(width: cell, height: cell)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.accent, lineWidth: selectedDay == day ? 1.5 : 0)
                        .padding(-2)
                )
                .contentShape(Rectangle())
                .help("\(date.formatted(.dateTime.month(.abbreviated).day())) · \(count) memo\(count == 1 ? "" : "s")")
                .onTapGesture {
                    guard count > 0 || selectedDay == day else { return }
                    selectedDay = selectedDay == day ? nil : day
                }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }
}

/// One day of memos, diary style (design board ㉜ B): the date hangs in a
/// column on the left — the day's number, then the weekday (and the month,
/// outside the current one) — with that day's memos beside it.
private struct MemoDayGroup<Content: View>: View {
    let day: String
    let isFirst: Bool
    @ViewBuilder let content: () -> Content

    static var dateColumn: CGFloat { 48 }

    private var date: Date? { MemoFormat.date(ofDay: day) }

    private var subtitle: String {
        guard let date else { return "" }
        let weekday = date.formatted(.dateTime.weekday(.abbreviated))
        let calendar = Calendar.current
        let now = Date()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            return weekday + " · " + date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
        if calendar.component(.month, from: date) != calendar.component(.month, from: now) {
            return weekday + " · " + date.formatted(.dateTime.month(.abbreviated))
        }
        return weekday
    }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .trailing, spacing: 5) {
                Text(date.map { String(Calendar.current.component(.day, from: $0)) } ?? day)
                    .font(Font(MemoTypography.font(size: 30)))
                    .foregroundColor(.primaryText)
                Text(subtitle)
                    .font(Font(MemoTypography.italic(size: 12)))
                    .foregroundColor(.faintText)
                    .fixedSize()
            }
            .frame(width: Self.dateColumn, alignment: .trailing)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            if !isFirst { Rectangle().fill(Color.borderColor).frame(height: 1) }
        }
    }
}

private struct FilterChip: View {
    let label: String
    let onClear: () -> Void

    var body: some View {
        Button(action: onClear) {
            HStack(spacing: 6) {
                Text(label).font(.notely(12))
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.sidebarBg))
        }
        .buttonStyle(.plain)
        .help("Show all memos")
    }
}

// MARK: - Memo row

/// One memo: its time, then the text. Hover for edit / copy / open the day's
/// file / delete.
private struct MemoRow: View {
    let memo: Memo
    let font: Font
    let onTag: (String) -> Void
    @Environment(FileNoteStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(memo.time)
                    .font(Font(MemoTypography.italic(size: 12.5)))
                    .monospacedDigit()
                    .foregroundColor(.faintText)
                Spacer(minLength: 0)
                menu.opacity(isHovering && !isEditing ? 1 : 0)
            }
            if isEditing {
                editor
            } else {
                Text(Self.attributed(memo.text, size: 15))
                    .font(font)
                    .lineSpacing(6)
                    .foregroundColor(.primaryText)
                    .tint(.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "notely-tag" else { return .systemAction }
                        onTag(url.host(percentEncoded: false) ?? "")
                        return .handled
                    })
            }
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .confirmationDialog("Delete this memo?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { store.deleteMemo(memo) }
        }
    }

    private var menu: some View {
        Menu {
            Button("Edit") {
                editText = memo.text
                isEditing = true
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(memo.text, forType: .string)
            }
            Button("Show in File") {
                if let note = store.memoNote(forDay: memo.day) { appModel.openNote(note.id) }
            }
            Divider()
            Button("Delete…", role: .destructive) { confirmingDelete = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.iconMuted)
                .frame(width: 24, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            MemoTextEditor(text: $editText, minHeight: 30, focusRequest: 1,
                           onSubmit: saveEdit, onCancel: { isEditing = false })
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.sidebarBg))
            HStack(spacing: 8) {
                SettingsButton(title: "Cancel") { isEditing = false }
                    .keyboardShortcut(.cancelAction)
                SettingsButton(title: "Save", action: saveEdit)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func saveEdit() {
        store.updateMemo(memo, text: editText)
        isEditing = false
    }

    /// The memo with inline Markdown (bold, italic, code, links) and its
    /// `#tags` as quiet, clickable runs.
    static func attributed(_ text: String, size: CGFloat) -> AttributedString {
        let ns = text as NSString
        func inline(_ s: String) -> AttributedString {
            (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(s)
        }
        var result = AttributedString()
        var cursor = 0
        for tag in MemoFormat.tagRanges(in: text) {
            if tag.range.location > cursor {
                result += inline(ns.substring(with: NSRange(location: cursor, length: tag.range.location - cursor)))
            }
            var run = AttributedString(ns.substring(with: tag.range))
            run.foregroundColor = Color.secondaryText
            run.backgroundColor = Color.inlineFill
            if let encoded = tag.name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
                run.link = URL(string: "notely-tag://" + encoded)
            }
            result += run
            cursor = NSMaxRange(tag.range)
        }
        if cursor < ns.length {
            result += inline(ns.substring(from: cursor))
        }
        MemoTypography.styleRuns(&result, size: size)
        return result
    }
}

/// Memos keeps the system title alone; with more than one tab open the
/// toolbar shows the tab strip instead, as over notes.
private struct MemosTabStrip: ViewModifier {
    @Environment(AppModel.self) private var appModel

    func body(content: Content) -> some View {
        if appModel.showsTabStrip {
            content
                .modifier(RemovesSystemTitle())
                .toolbar { NoteTitleHeader() }
        } else {
            content
        }
    }
}
