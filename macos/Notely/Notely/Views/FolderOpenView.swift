import SwiftUI

/// Shown when no workspace folder is open.
struct FolderOpenView: View {
    @Environment(FileNoteStore.self) var store

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.accent.opacity(0.08))
                    .frame(width: 88, height: 88)
                Image(systemName: "folder")
                    .font(.system(size: 38, weight: .light))
                    .foregroundColor(.accent)
            }

            VStack(spacing: 8) {
                Text("Open a Folder")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primaryText)

                Text("Choose a folder containing your Markdown notes.")
                    .font(.system(size: 14))
                    .foregroundColor(.tertiaryText)
            }

            Button {
                openFolderPanel()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14))
                    Text("Open Folder")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accent)
                )
            }
            .buttonStyle(.plain)

            if let url = store.workspaceURL {
                Text(url.path)
                    .font(.system(size: 12))
                    .foregroundColor(.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.editorBg)
    }

    private func openFolderPanel() {
        guard let url = NotesFolderPanel.choose() else { return }
        store.openWorkspace(at: url)
    }
}

/// The "Open Notes Folder" panel, shared by the empty state, the sidebar's
/// workspace menu and the ⌘O command.
enum NotesFolderPanel {
    static func choose() -> URL? {
        let panel = NSOpenPanel()
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
