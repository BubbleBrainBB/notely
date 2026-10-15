import SwiftUI

/// First launch (no folder open yet), design board ㉕: the name, one line,
/// and two choices — a new notebook in Documents, or a folder the user
/// already has. The name is a placeholder until the product is named.
struct FolderOpenView: View {
    @Environment(FileNoteStore.self) var store
    @Environment(AppModel.self) var appModel
    @State private var appeared = false
    @State private var isHoveringNew = false
    @State private var isHoveringOpen = false
    @State private var errorMessage: String?

    static let productName = "Notely"

    var body: some View {
        VStack(spacing: 0) {
            Text(Self.productName)
                .font(.custom("Didot-Italic", size: 76))
                .tracking(-0.5)
                .foregroundColor(Color.fromHex("#2B2A26"))
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.notely(11.5))
                    .foregroundColor(.tertiaryText)
                    .padding(.top, 20)
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: appeared)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fromHex("#FDFDFC"))
        .ignoresSafeArea()
        .navigationTitle("")
        // One surface up to the top edge: no toolbar strip, no separator line
        // under the traffic lights.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear { appeared = true }
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
        store.openWorkspace(at: folder)
        appModel.openNote(store.createNote()?.id)
    }

    private func openExistingFolder() {
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
