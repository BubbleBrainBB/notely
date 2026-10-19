import SwiftUI

/// No folder open (design boards ㉕, ㉞): the name, one line, and two
/// choices — a new notebook in Documents, or a folder the user already has —
/// plus the folders opened before. When the last session's folder can't be
/// found, it says so instead and offers to find it. The name is a
/// placeholder until the product is named.
struct FolderOpenView: View {
    @Environment(FileNoteStore.self) var store
    @Environment(AppModel.self) var appModel
    @State private var appeared = false
    @State private var isHoveringNew = false
    @State private var isHoveringOpen = false
    @State private var errorMessage: String?

    static let productName = "Notely"

    var body: some View {
        Group {
            if let missing = store.missingWorkspace {
                MissingFolderPanel(url: missing,
                                   locate: { locate(missing) },
                                   openOther: openExistingFolder,
                                   newNotebook: startNewNotebook,
                                   reappeared: { open(missing) })
            } else {
                welcome
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: appeared)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.editorBg)
        .ignoresSafeArea()
        .navigationTitle("")
        // One surface up to the top edge: no toolbar strip, no separator line
        // under the traffic lights.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear { appeared = true }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Text(Self.productName)
                .font(.custom("Didot-Italic", size: 76))
                .tracking(-0.5)
                .foregroundColor(.primaryText)
            Text("Your notes, as plain files.")
                .font(Font(WysiwygEngine.resolveFont(name: "New York", size: 15)))
                .foregroundColor(.tertiaryText)
                .padding(.top, 18)

            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 6) {
                    Button(action: startNewNotebook) {
                        HStack(spacing: 6) {
                            Text("New Notebook")
                                .font(.notely(13, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .medium))
                                .offset(x: isHoveringNew ? 2 : 0)
                        }
                        .foregroundColor(.primaryText)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.primaryText).frame(height: 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .onHover { isHoveringNew = $0 }
                    .animation(.easeOut(duration: 0.15), value: isHoveringNew)
                    Text("in Documents")
                        .font(.notely(11))
                        .foregroundColor(.faintText)
                }

                Button(action: openExistingFolder) {
                    Text("Open Folder…")
                        .font(.notely(13))
                        .foregroundColor(isHoveringOpen ? .primaryText : .tertiaryText)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringOpen = $0 }
            }
            .padding(.top, 64)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.3), value: appeared)

            // Folders opened before; never shown on a first launch.
            let recents = RecentFolder.existing()
            if !recents.isEmpty {
                RecentFolderList(folders: recents, open: open)
                    .padding(.top, 48)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.45), value: appeared)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.notely(11.5))
                    .foregroundColor(.tertiaryText)
                    .padding(.top, 20)
            }
        }
    }

    /// Opens a library from this page, handing over to the main window with
    /// the frame-in transition.
    private func open(_ url: URL) {
        appModel.beginFrameIntro()
        store.openWorkspace(at: url)
    }

    /// The folder panel, starting where the missing folder used to be.
    private func locate(_ missing: URL) {
        guard let url = NotesFolderPanel.choose(startingAt: missing) else { return }
        open(url)
    }

    /// Makes (or reuses) Documents/Notely and opens a first, blank note.
    private func startNewNotebook() {
        let fm = FileManager.default
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent(Self.productName, isDirectory: true)
        var isDirectory: ObjCBool = false
        do {
            if !fm.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            } else if !isDirectory.boolValue {
                errorMessage = "A file named \(Self.productName) is already in Documents."
                return
            }
        } catch {
            errorMessage = "Couldn't create the folder: \(error.localizedDescription)"
            return
        }
        open(folder)
        appModel.openNote(store.createNote()?.id)
    }

    private func openExistingFolder() {
        guard let url = NotesFolderPanel.choose() else { return }
        open(url)
    }
}

/// The "Open Notes Folder" panel, shared by the empty state, the sidebar's
/// workspace menu and the ⌘O command.
enum NotesFolderPanel {
    /// `startingAt`: open the panel at this folder, or at its nearest parent
    /// that still exists.
    static func choose(startingAt start: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        if var dir = start {
            while dir.pathComponents.count > 1, !FileManager.default.fileExists(atPath: dir.path) {
                dir.deleteLastPathComponent()
            }
            panel.directoryURL = dir
        }
        panel.title = "Open Notes Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

// MARK: - Recent folders

struct RecentFolder: Identifiable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    /// Where it lives, as Finder names it: "Documents", "iCloud Drive"…
    var location: String {
        FileManager.default.displayName(atPath: url.deletingLastPathComponent().path)
    }

    /// The recent folders that are still on disk, most recent first.
    static func existing() -> [RecentFolder] {
        AppSettings.recentWorkspaces
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { RecentFolder(url: URL(fileURLWithPath: $0)) }
    }
}

private struct RecentFolderList: View {
    let folders: [RecentFolder]
    let open: (URL) -> Void
    @State private var hoveredId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent")
                .font(.notely(11, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.faintText)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            ForEach(folders) { folder in
                Button { open(folder.url) } label: {
                    HStack(spacing: 9) {
                        ShiyeIcon(.library, size: 15)
                            .foregroundColor(.iconMuted)
                        Text(BodyFace.text(folder.name, fontName: "New York", size: 14))
                            .foregroundColor(.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Text(folder.location)
                            .font(.notely(11.5))
                            .foregroundColor(.faintText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(hoveredId == folder.id ? Color.cardHover : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredId = $0 ? folder.id : (hoveredId == folder.id ? nil : hoveredId) }
            }
        }
        .frame(width: 360)
    }
}

// MARK: - Missing folder

/// The last session's folder can't be found (design board ㉞ ④). On a disk
/// that isn't connected it waits, and opens the folder once the disk mounts;
/// otherwise it offers to find the folder where it went.
private struct MissingFolderPanel: View {
    let url: URL
    let locate: () -> Void
    let openOther: () -> Void
    let newNotebook: () -> Void
    /// The folder is back (its disk mounted): open it.
    let reappeared: () -> Void
    @State private var isHoveringLocate = false
    @State private var hovered: String?

    /// The disk's name when the folder lives on a volume that isn't mounted.
    private var unmountedVolume: String? {
        let parts = url.pathComponents
        guard parts.count > 2, parts[1] == "Volumes" else { return nil }
        return FileManager.default.fileExists(atPath: "/Volumes/" + parts[2]) ? nil : parts[2]
    }

    /// "Documents › My Notes", "iCloud Drive › My Notes", "T7 › Notes › My Notes".
    private var breadcrumb: String {
        var parts = url.pathComponents
        let home = FileManager.default.homeDirectoryForCurrentUser.pathComponents
        if parts.starts(with: home) {
            parts.removeFirst(home.count)
            let iCloud = ["Library", "Mobile Documents", "com~apple~CloudDocs"]
            if parts.starts(with: iCloud) { parts.replaceSubrange(0..<iCloud.count, with: ["iCloud Drive"]) }
        } else if parts.count > 2, parts[1] == "Volumes" {
            parts.removeFirst(2)
        } else {
            parts.removeFirst()
        }
        return parts.suffix(3).joined(separator: " › ")
    }

    var body: some View {
        let volume = unmountedVolume
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: volume == nil ? "questionmark.folder" : "externaldrive")
                .font(.system(size: 19, weight: .light))
                .foregroundColor(.iconMuted)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.inlineFill))
                .padding(.bottom, 20)

            Text(BodyFace.text(volume == nil
                                ? "Can’t find “\(url.lastPathComponent)”"
                                : "“\(url.lastPathComponent)” is on a disk that isn’t connected",
                               fontName: "New York", size: 20, weight: .semibold))
                .foregroundColor(.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(breadcrumb)
                .font(.notely(12))
                .foregroundColor(.faintText)
                .padding(.top, 6)
            Text(volume.map { "It opens once “\($0)” is connected." } ?? "It may have been moved, renamed or deleted.")
                .font(.notely(13))
                .foregroundColor(.tertiaryText)
                .padding(.top, 12)

            if volume != nil {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.fromHex("#E0A93B"))
                        .frame(width: 6, height: 6)
                        .background(Circle().fill(Color.fromHex("#E0A93B").opacity(0.18)).frame(width: 12, height: 12))
                    Text("Waiting for the disk…")
                        .font(.notely(12))
                        .foregroundColor(.faintText)
                }
                .padding(.top, 14)
            }

            HStack(alignment: .firstTextBaseline, spacing: 24) {
                if volume == nil {
                    Button(action: locate) {
                        HStack(spacing: 6) {
                            Text("Locate…").font(.notely(13, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .medium))
                                .offset(x: isHoveringLocate ? 2 : 0)
                        }
                        .foregroundColor(.primaryText)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.primaryText).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .onHover { isHoveringLocate = $0 }
                    .animation(.easeOut(duration: 0.15), value: isHoveringLocate)
                }
                quietButton("Open Another Folder…", action: openOther)
                quietButton("New Notebook", action: newNotebook)
            }
            .padding(.top, 28)
        }
        .frame(width: 420, alignment: .leading)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            if FileManager.default.fileExists(atPath: url.path) { reappeared() }
        }
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.notely(13))
                .foregroundColor(hovered == title ? .primaryText : .tertiaryText)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? title : (hovered == title ? nil : hovered) }
    }
}
