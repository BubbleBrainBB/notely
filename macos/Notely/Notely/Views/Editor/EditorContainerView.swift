import SwiftUI

/// Right column: wraps the editor or shows empty state.
struct EditorContainerView: View {
    @Environment(AppModel.self) var appModel
    @Environment(FileNoteStore.self) var store

    var body: some View {
        Group {
            if let noteId = appModel.selectedNoteId,
               let note = store.notes.first(where: { $0.id == noteId }) {
                EditorView(note: note)
                    .id(note.id)
            } else {
                EmptyEditorView()
            }
        }
        .background(Color.editorBg)
    }
}

/// Shown when no note is selected.
struct EmptyEditorView: View {
    @Environment(AppModel.self) var appModel
    @Environment(FileNoteStore.self) var store

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ShiyeIcon(.note, size: 28)
                    .foregroundColor(.iconMuted)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.sidebarBg))

                VStack(spacing: 4) {
                    Text("No note open")
                        .font(.notely(15, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Text("Pick one from the sidebar, or start a new one.")
                        .font(.notely(13))
                        .foregroundColor(.tertiaryText)
                }

                Button {
                    appModel.openNote(store.createNote()?.id)
                } label: {
                    Text("New Note")
                        .font(.notely(13, weight: .medium))
                        .foregroundColor(.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.surface))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.controlBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.editorBg)
        .modifier(NoteToolbar())
    }
}
